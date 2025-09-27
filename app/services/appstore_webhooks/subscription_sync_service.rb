# frozen_string_literal: true

module AppstoreWebhooks
  class SubscriptionSyncService
    EVENT_MAP = {
      'SUBSCRIBED'              => :activate,
      'DID_RENEW'               => :activate,
      'DID_RECOVER'             => :activate,
      'OFFER_REDEEMED'          => :activate,
      'RENEWAL_EXTENDED'        => :activate,
      'RENEWAL_EXTENSION'       => :activate,
      'REFUND_REVERSED'         => :activate,
      'DID_FAIL_TO_RENEW'       => :handle_fail_to_renew,
      'GRACE_PERIOD_EXPIRED'    => :expire,
      'EXPIRED'                 => :expire,
      'DID_CHANGE_RENEWAL_STATUS' => :handle_change_renewal_status,
      'REVOKE'                  => :revoke,
      'REFUND'                  => :refund
    }.freeze

    def initialize(notification:, transaction_payload:, renewal_payload: {})
      @notification = notification
      @transaction_payload = (transaction_payload || {}).with_indifferent_access
      @renewal_payload = (renewal_payload || {}).with_indifferent_access
    end

    def call(subscription)
      handler = EVENT_MAP[@notification.notification_type]
      return subscription unless handler

      if handler.is_a?(Symbol) && subscription.respond_to?(handler)
        trigger_event(subscription, handler)
      else
        send(handler, subscription)
      end

      subscription
    end

    private

    attr_reader :notification, :transaction_payload, :renewal_payload

    def handle_fail_to_renew(subscription)
      grace_expires = fetch_value(transaction_payload, :grace_period_expires_date)
      status_code = fetch_value(transaction_payload, :status)

      if grace_expires.present? || status_code.to_s == '4'
        trigger_event(subscription, :start_grace)
      else
        trigger_event(subscription, :enter_billing_retry)
      end
    end

    def handle_change_renewal_status(subscription)
      subtype = notification.subtype
      if subtype == 'AUTO_RENEW_DISABLED'
        trigger_event(subscription, :cancel_auto_renew, auto_renew_override: false)
      else
        trigger_event(subscription, :activate)
      end
    end

    def fetch_value(payload, key)
      payload[key] || payload[key.to_s] || payload[key.to_s.camelize(:lower)]
    end

    def trigger_event(subscription, event_name, auto_renew_override: nil)
      payload = effective_payload.presence || {}
      args = {
        payload: payload,
        renewal_payload: renewal_payload.presence || {},
        auto_renew: auto_renew_override
      }
      subscription.public_send("#{event_name}!", **args)
    rescue AASM::TransitionInvalid => e
      Rails.logger.error("Failed to transition subscription ##{subscription.id} via #{event_name}: #{e.message}")
      raise
    end

    def effective_payload
      transaction_payload.presence || renewal_payload
    end
  end
end
