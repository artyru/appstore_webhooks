# frozen_string_literal: true

module AppstoreWebhooks
  class ProcessNotificationWorker < ApplicationJob
    queue_as :default

    def perform(payload_hash)
      notification = nil

      payload = AppstoreSDK::Models::ResponseBodyV2DecodedPayload.from_hash(payload_hash)
      signed_data_verifier = build_signed_data_verifier

      transaction_payload = decode_transaction_payload(payload, signed_data_verifier)
      renewal_payload = decode_renewal_payload(payload, signed_data_verifier)

      notification = upsert_notification(payload, payload_hash, transaction_payload, renewal_payload)

      if notification.notification_type == 'CONSUMPTION_REQUEST'
        AppstoreWebhooks::RespondToConsumptionRequestJob.perform_later(notification.id)
        return
      end

      process_subscription_notification(notification, transaction_payload, renewal_payload)
    rescue StandardError => e
      notification&.update(processing_state: Notification::STATES[:failed],
                           processing_error: e.message)
      ::Rails.logger.error("Failed to process App Store notification: #{e.message}")
      raise
    end

    private

    def build_signed_data_verifier
      AppstoreSDK::Verification::SignedDataVerifier.new(
        AppstoreSDK.configuration.root_certificates,
        AppstoreSDK.configuration.enable_online_checks,
        AppstoreSDK.configuration.environment,
        AppstoreSDK.configuration.bundle_id,
        app_apple_id:   AppstoreSDK.configuration.app_apple_id,
        chain_verifier: AppstoreSDK.configuration.chain_verifier,
        cache:          AppstoreSDK.configuration.cache
      )
    end

    def decode_transaction_payload(payload, verifier)
      signed_tx = payload.data&.signed_transaction_info
      return {} unless signed_tx

      result = verifier.verify_and_decode_signed_transaction(signed_tx)
      normalize_keys(result.to_h)
    end

    def decode_renewal_payload(payload, verifier)
      signed_rx = payload.data&.signed_renewal_info
      return {} unless signed_rx

      result = verifier.verify_and_decode_renewal_info(signed_rx)
      normalize_keys(result.to_h)
    end

    def upsert_notification(payload, raw_payload, transaction_payload, renewal_payload)
      attrs = {
        notification_type: payload.notification_type,
        subtype: payload.subtype,
        app_account_token: transaction_payload[:app_account_token],
        raw_payload: raw_payload,
        transaction_payload: transaction_payload,
        processing_state: Notification::STATES[:processing]
      }

      notification = Notification.find_or_initialize_by(notification_uuid: payload.notification_uuid)
      attrs[:renewal_payload] = renewal_payload if notification.respond_to?(:renewal_payload=)
      notification.assign_attributes(attrs)

      if (subscription = Subscription.find_by(original_transaction_id: transaction_payload[:original_transaction_id]))
        notification.subscription = subscription
      end

      notification.save!
      notification
    end

    def normalize_keys(hash)
      return {} unless hash

      hash.deep_transform_keys { |key| key.to_s.underscore }.with_indifferent_access
    end

    def process_subscription_notification(notification, transaction_payload, renewal_payload)
      effective_payload = transaction_payload.presence || renewal_payload

      if effective_payload.blank?
        notification.update!(processing_state: Notification::STATES[:processed],
                             processing_error: nil)
        return
      end

      subscription = locate_or_create_subscription(effective_payload, renewal_payload)

      unless subscription
        notify_missing_user(notification, effective_payload[:app_account_token])
        return
      end

      previous_status = subscription.status
      event_timestamp = determine_event_timestamp(transaction_payload, renewal_payload, effective_payload)

      if skip_stale_event?(subscription, event_timestamp)
        notification.update!(subscription: subscription,
                             processing_state: Notification::STATES[:processed],
                             processing_error: nil)
        return
      end

      SubscriptionSyncService.new(
        notification: notification,
        transaction_payload: transaction_payload,
        renewal_payload: renewal_payload
      ).call(subscription)

      subscription.reload

      create_subscription_event(subscription, notification, previous_status, transaction_payload, renewal_payload, effective_payload)

      notification.update!(subscription: subscription,
                           processing_state: Notification::STATES[:processed],
                           processing_error: nil)
    end

    def locate_or_create_subscription(payload, renewal_payload)
      original_transaction_id = payload[:original_transaction_id]
      return nil if original_transaction_id.blank?

      subscription = Subscription.find_or_initialize_by(original_transaction_id: original_transaction_id)

      if subscription.new_record?
        user = find_user_for_transaction(payload, renewal_payload)
        return nil unless user

        subscription.user = user
        subscription.app_account_token = payload[:app_account_token] || user.public_send(AppstoreWebhooks.configuration.user_token_column)
        subscription.product_id = payload[:product_id]
        subscription.environment = derive_environment(payload)
        subscription.expires_at = extract_timestamp(payload[:expires_date])
        subscription.grace_period_expires_at = extract_timestamp(payload[:grace_period_expires_date])
        subscription.last_synced_at = Time.current
        subscription.save!
      end

      subscription
    end

    def find_user_for_transaction(payload, renewal_payload)
      token_column = AppstoreWebhooks.configuration.user_token_column
      app_account_token = payload[:app_account_token] || renewal_payload[:app_account_token]
      return nil unless app_account_token.present?

      user_class = AppstoreWebhooks.configuration.user_class_constant
      user_class.where(token_column => app_account_token).first
    end

    def notify_missing_user(notification, app_account_token)
      notification.update!(
        processing_state: Notification::STATES[:failed],
        processing_error: "User not found for app_account_token #{app_account_token}"
      )

      AppstoreWebhooks::NotifyMissingUserJob.perform_later(notification.id, app_account_token)
    end

    def determine_event_timestamp(transaction_payload, renewal_payload, effective_payload)
      candidates = [
        transaction_payload[:signed_date],
        transaction_payload[:event_date],
        transaction_payload[:purchase_date],
        transaction_payload[:expires_date],
        renewal_payload[:signed_date],
        renewal_payload[:event_date],
        renewal_payload[:renewal_date],
        renewal_payload[:expires_date],
        effective_payload[:signed_date],
        effective_payload[:event_date],
        effective_payload[:purchase_date],
        effective_payload[:expires_date]
      ].compact

      candidates.each do |value|
        timestamp = extract_timestamp(value)
        return timestamp if timestamp
      end

      nil
    end

    def skip_stale_event?(subscription, event_timestamp)
      return false if event_timestamp.nil?
      return false if subscription.previous_changes.key?('id')
      return false unless subscription.last_synced_at.present?

      event_timestamp <= subscription.last_synced_at
    end

    def derive_environment(payload)
      environment = payload[:environment]
      return environment.to_s.underscore if environment.respond_to?(:to_s)

      environment
    end

    def extract_timestamp(value)
      return if value.blank?

      if value.is_a?(Integer)
        Time.zone.at(value / 1000.0)
      elsif value.is_a?(String) && value.match?(/^\d+$/)
        Time.zone.at(value.to_i / 1000.0)
      else
        Time.zone.parse(value.to_s)
      end
    rescue ArgumentError
      nil
    end

    def create_subscription_event(subscription, notification, previous_status, transaction_payload, renewal_payload, effective_payload)
      SubscriptionEvent.create!(
        subscription: subscription,
        webhook_notification: notification,
        previous_status: previous_status,
        next_status: subscription.status,
        effective_at: Time.current,
        metadata: {
          notification_type: notification.notification_type,
          subtype: notification.subtype,
          transaction_id: transaction_payload[:transaction_id],
          original_transaction_id: effective_payload[:original_transaction_id],
          environment: effective_payload[:environment] || renewal_payload[:environment],
          expires_date: transaction_payload[:expires_date],
          renewal_date: renewal_payload[:renewal_date],
          auto_renew_status: renewal_payload[:auto_renew_status] || renewal_payload[:raw_auto_renew_status]
        }.compact
      )
    end
  end
end
