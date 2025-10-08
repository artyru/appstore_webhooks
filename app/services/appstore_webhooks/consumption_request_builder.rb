# frozen_string_literal: true

module AppstoreWebhooks
  class ConsumptionRequestBuilder
    def initialize(subscription:, transaction_payload:)
      @subscription = subscription
      @transaction_payload = (transaction_payload || {}).with_indifferent_access
    end

    def call(consented: true, consumption_status: nil)
      AppstoreSDK::Models::ConsumptionRequest.new(
        customer_consented: consented,
        consumption_status: resolve_consumption_status(consumption_status),
        platform: AppstoreSDK::Models::Platform::APPLE,
        delivery_status: resolve_delivery_status,
        app_account_token: app_account_token,
        lifetime_dollars_purchased: bucket_amount(total_purchased_cents,
                                                  AppstoreSDK::Models::LifetimeDollarsPurchased),
        lifetime_dollars_refunded: bucket_amount(total_refunded_cents,
                                                 AppstoreSDK::Models::LifetimeDollarsRefunded),
        play_time: bucket_play_time,
        account_tenure: bucket_account_tenure,
        refund_preference: AppstoreSDK::Models::RefundPreference::NO_PREFERENCE
      )
    end

    private

    attr_reader :subscription, :transaction_payload

    def resolve_consumption_status(override)
      return AppstoreSDK::Models::ConsumptionStatus.from(override) if override

      return AppstoreSDK::Models::ConsumptionStatus::NOT_CONSUMED if subscription&.refunded? || subscription&.revoked?
      return AppstoreSDK::Models::ConsumptionStatus::PARTIALLY_CONSUMED if subscription&.billing_retry?

      status_code = transaction_payload[:status]&.to_i

      case status_code
      when 5
        AppstoreSDK::Models::ConsumptionStatus::NOT_CONSUMED
      when 4, 3
        AppstoreSDK::Models::ConsumptionStatus::PARTIALLY_CONSUMED
      when 1
        AppstoreSDK::Models::ConsumptionStatus::FULLY_CONSUMED
      when 2
        AppstoreSDK::Models::ConsumptionStatus::PARTIALLY_CONSUMED
      else
        fallback_consumption_status
      end
    end

    def fallback_consumption_status
      return AppstoreSDK::Models::ConsumptionStatus::UNDECLARED unless subscription

      if subscription.refunded? || subscription.revoked?
        AppstoreSDK::Models::ConsumptionStatus::NOT_CONSUMED
      elsif subscription.active? || subscription.grace? || subscription.billing_retry?
        AppstoreSDK::Models::ConsumptionStatus::FULLY_CONSUMED
      elsif subscription.expired? || subscription.canceled?
        AppstoreSDK::Models::ConsumptionStatus::PARTIALLY_CONSUMED
      else
        AppstoreSDK::Models::ConsumptionStatus::UNDECLARED
      end
    end

    def resolve_delivery_status
      return AppstoreSDK::Models::DeliveryStatus::DELIVERED_AND_WORKING_PROPERLY unless subscription

      if subscription.refunded?
        AppstoreSDK::Models::DeliveryStatus::DID_NOT_DELIVER_FOR_OTHER_REASON
      elsif subscription.revoked?
        AppstoreSDK::Models::DeliveryStatus::DID_NOT_DELIVER_DUE_TO_QUALITY_ISSUE
      else
        AppstoreSDK::Models::DeliveryStatus::DELIVERED_AND_WORKING_PROPERLY
      end
    end

    def app_account_token
      transaction_payload[:app_account_token] || subscription&.app_account_token
    end

    def total_purchased_cents
      return transaction_payload[:price].to_i unless subscription

      cached = subscription.respond_to?(:lifetime_purchased_cents) && subscription.lifetime_purchased_cents
      return cached if cached

      notifications = Array(subscription.notifications)

      total = notifications.sum do |notification|
        payload = notification.transaction_payload || {}
        payload["price"].to_i
      end

      total += transaction_payload[:price].to_i if total.zero?
      total
    end

    def total_refunded_cents
      return 0 unless subscription

      cached = subscription.respond_to?(:lifetime_refunded_cents) && subscription.lifetime_refunded_cents
      return cached if cached

      Array(subscription.notifications).select do |notification|
        %w[REFUND REFUND_REVERSED].include?(notification.notification_type)
      end.sum { |notification| (notification.transaction_payload || {})["price"].to_i }
    end

    def bucket_amount(cents, enum_klass)
      return enum_klass::UNDECLARED if cents.nil?

      cents = cents.to_i

      case cents
      when 0
        enum_klass::ZERO_DOLLARS
      when 1..4_999
        enum_klass::ONE_CENT_TO_FORTY_NINE_DOLLARS_AND_NINETY_NINE_CENTS
      when 5_000..9_999
        enum_klass::FIFTY_DOLLARS_TO_NINETY_NINE_DOLLARS_AND_NINETY_NINE_CENTS
      when 10_000..49_999
        enum_klass::ONE_HUNDRED_DOLLARS_TO_FOUR_HUNDRED_NINETY_NINE_DOLLARS_AND_NINETY_NINE_CENTS
      when 50_000..99_999
        enum_klass::FIVE_HUNDRED_DOLLARS_TO_NINE_HUNDRED_NINETY_NINE_DOLLARS_AND_NINETY_NINE_CENTS
      when 100_000..199_999
        enum_klass::ONE_THOUSAND_DOLLARS_TO_ONE_THOUSAND_NINE_HUNDRED_NINETY_NINE_DOLLARS_AND_NINETY_NINE_CENTS
      else
        enum_klass::TWO_THOUSAND_DOLLARS_OR_GREATER
      end
    end

    def bucket_play_time
      minutes = usage_minutes

      case minutes
      when nil
        AppstoreSDK::Models::PlayTime::UNDECLARED
      when 0..5
        AppstoreSDK::Models::PlayTime::ZERO_TO_FIVE_MINUTES
      when 5...60
        AppstoreSDK::Models::PlayTime::FIVE_TO_SIXTY_MINUTES
      when 60...360
        AppstoreSDK::Models::PlayTime::ONE_TO_SIX_HOURS
      when 360...1_440
        AppstoreSDK::Models::PlayTime::SIX_HOURS_TO_TWENTY_FOUR_HOURS
      when 1_440...5_760
        AppstoreSDK::Models::PlayTime::ONE_DAY_TO_FOUR_DAYS
      when 5_760...23_040
        AppstoreSDK::Models::PlayTime::FOUR_DAYS_TO_SIXTEEN_DAYS
      else
        AppstoreSDK::Models::PlayTime::OVER_SIXTEEN_DAYS
      end
    end

    def usage_minutes
      return nil unless subscription&.created_at

      end_time = subscription.last_synced_at || Time.current
      duration = end_time - subscription.created_at
      return 0 if duration.negative?

      (duration / 60.0).round
    end

    def bucket_account_tenure
      user = subscription&.user
      return AppstoreSDK::Models::AccountTenure::UNDECLARED unless user&.created_at

      days_active = (Time.current.to_date - user.created_at.to_date).to_i

      case days_active
      when 0..3
        AppstoreSDK::Models::AccountTenure::ZERO_TO_THREE_DAYS
      when 4..10
        AppstoreSDK::Models::AccountTenure::THREE_DAYS_TO_TEN_DAYS
      when 11..30
        AppstoreSDK::Models::AccountTenure::TEN_DAYS_TO_THIRTY_DAYS
      when 31..90
        AppstoreSDK::Models::AccountTenure::THIRTY_DAYS_TO_NINETY_DAYS
      when 91..180
        AppstoreSDK::Models::AccountTenure::NINETY_DAYS_TO_ONE_HUNDRED_EIGHTY_DAYS
      when 181..365
        AppstoreSDK::Models::AccountTenure::ONE_HUNDRED_EIGHTY_DAYS_TO_THREE_HUNDRED_SIXTY_FIVE_DAYS
      else
        AppstoreSDK::Models::AccountTenure::GREATER_THAN_THREE_HUNDRED_SIXTY_FIVE_DAYS
      end
    end
  end
end
