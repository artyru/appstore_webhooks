# frozen_string_literal: true

module AppstoreWebhooks
  class SyncSubscriptionJob < ApplicationJob
    queue_as :default

    def perform(subscription_id: nil, original_transaction_id: nil, client: nil)
      subscription = resolve_subscription(subscription_id, original_transaction_id)
      original_transaction_id ||= subscription&.original_transaction_id

      raise ArgumentError, "original_transaction_id is required" if original_transaction_id.to_s.empty?

      log_missing_subscription(original_transaction_id) unless subscription

      result = RemoteSubscriptionSyncService.new(
        subscription: subscription,
        original_transaction_id: original_transaction_id,
        client: client
      ).call

      subscription.reload if subscription&.persisted?

      result
    rescue StandardError => e
      log_failure(original_transaction_id, e)
      raise
    end

    private

    def resolve_subscription(subscription_id, original_transaction_id)
      if subscription_id
        AppstoreWebhooks::Subscription.find_by(id: subscription_id)
      elsif original_transaction_id
        AppstoreWebhooks::Subscription.find_by(original_transaction_id: original_transaction_id)
      end
    end

    def log_missing_subscription(original_transaction_id)
      return unless defined?(Rails) && Rails.logger

      Rails.logger.info(
        "[appstore_webhooks] remote sync requested without local subscription for #{original_transaction_id}"
      )
    end

    def log_failure(original_transaction_id, error)
      return unless defined?(Rails) && Rails.logger

      identifier = original_transaction_id.presence || "unknown"
      Rails.logger.error(
        "[appstore_webhooks] failed remote sync for #{identifier}: #{error.message}"
      )
    end
  end
end
