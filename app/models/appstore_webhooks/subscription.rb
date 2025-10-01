# frozen_string_literal: true

module AppstoreWebhooks
  class Subscription < ApplicationRecord
    include AASM

    self.table_name = 'subscriptions'

    STATUSES = {
      active:        'active',
      grace:         'grace',
      billing_retry: 'billing_retry',
      expired:       'expired',
      canceled:      'canceled',
      revoked:       'revoked',
      refunded:      'refunded'
    }.freeze

    belongs_to :user,
               class_name: -> { AppstoreWebhooks.configuration.user_class }.call
    has_many :events,
             class_name: 'AppstoreWebhooks::SubscriptionEvent',
             dependent: :destroy
    has_many :notifications,
             class_name: 'AppstoreWebhooks::Notification',
             dependent: :nullify

    enum :status, STATUSES

    validates :original_transaction_id, presence: true, uniqueness: true
    validates :app_account_token, presence: true
    validates :status, inclusion: { in: STATUSES.values }
    validates :expires_at, presence: true

    aasm column: :status, enum: true do
      state :active, initial: true
      state :grace
      state :billing_retry
      state :expired
      state :canceled
      state :revoked
      state :refunded

      event :activate do
        transitions from: %i[active grace billing_retry expired canceled refunded],
                   to: :active,
                   after: :apply_payload
      end

      event :start_grace do
        transitions from: %i[active billing_retry canceled],
                   to: :grace,
                   after: :apply_payload
      end

      event :enter_billing_retry do
        transitions from: %i[active grace canceled],
                   to: :billing_retry,
                   after: :apply_payload
      end

      event :expire do
        transitions from: %i[active grace billing_retry canceled],
                   to: :expired,
                   after: :apply_payload
      end

      event :cancel_auto_renew do
        transitions from: %i[active grace billing_retry],
                   to: :canceled,
                   after: :apply_payload
      end

      event :revoke do
        transitions from: %i[active grace billing_retry expired canceled],
                   to: :revoked,
                   after: :apply_payload
      end

      event :refund do
        transitions from: %i[active grace billing_retry canceled expired],
                   to: :refunded,
                   after: :apply_payload
      end
    end

    def sync_from_transaction(payload:, renewal_payload: nil, auto_renew: nil)
      data = payload || {}
      attrs = {
        product_id: fetch_value(data, :product_id),
        app_account_token: fetch_value(data, :app_account_token) || app_account_token,
        expires_at: extract_datetime(data, :expires_date),
        grace_period_expires_at: extract_datetime(data, :grace_period_expires_date),
        last_synced_at: Time.current
      }

      if (env = fetch_value(data, :environment))
        attrs[:environment] = env.to_s.underscore
      end

      resolved_auto_renew = auto_renew.nil? ? derive_auto_renew_status(renewal_payload) : auto_renew
      attrs[:auto_renew_status] = resolved_auto_renew unless resolved_auto_renew.nil?

      update!(attrs.compact)
    end

    def active?
      super && expires_at.future?
    end

    def entitlement_active?(at: nil)
      moment = at || Time.current

      return false if expires_at.blank?

      if canceled?
        expires_at > moment
      else
        expires_at > moment || (grace_period_expires_at.present? && grace_period_expires_at > moment)
      end
    end

    private

    def fetch_value(payload, key)
      payload[key] || payload[key.to_s] || payload[key.to_s.camelize(:lower)]
    end

    def extract_datetime(payload, key)
      raw = fetch_value(payload, key)
      return if raw.blank?

      case raw
      when Time then raw.in_time_zone
      when DateTime, ActiveSupport::TimeWithZone then raw.in_time_zone
      when Integer then Time.zone.at(raw / 1000.0)
      when String
        if raw.match?(/^\d+$/)
          Time.zone.at(raw.to_i / 1000.0)
        else
          Time.zone.parse(raw)
        end
      end
    rescue ArgumentError
      nil
    end

    def apply_payload(payload:, renewal_payload: nil, auto_renew: nil)
      sync_from_transaction(
        payload: payload,
        renewal_payload: renewal_payload,
        auto_renew: auto_renew
      )
    end

    def derive_auto_renew_status(renewal_payload)
      return if renewal_payload.blank?

      value = fetch_value(renewal_payload, :auto_renew_status)
      value = fetch_value(renewal_payload, :raw_auto_renew_status) if value.nil?
      return if value.nil?

      value.to_s == '1'
    end
  end
end
