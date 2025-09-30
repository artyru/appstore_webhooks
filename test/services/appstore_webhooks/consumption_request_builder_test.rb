# frozen_string_literal: true

require 'test_helper'

module AppstoreWebhooks
  class ConsumptionRequestBuilderTest < ActiveSupport::TestCase
    def setup
      @subscription = create_subscription(
        status: 'active',
        created_at: 10.days.ago,
        last_synced_at: Time.current,
        app_account_token: SecureRandom.uuid
      )
      @transaction_payload = {
        original_transaction_id: @subscription.original_transaction_id,
        transaction_id: '2000000000001',
        app_account_token: @subscription.app_account_token,
        price: 29_900,
        status: 1
      }
    end

    def test_builds_consumption_request_with_defaults
      request = builder.call

      assert_equal true, request.customer_consented
      assert_equal @subscription.app_account_token, request.app_account_token
      assert_equal AppstoreSDK::Models::ConsumptionStatus::FULLY_CONSUMED, request.consumption_status
      assert_equal AppstoreSDK::Models::DeliveryStatus::DELIVERED_AND_WORKING_PROPERLY, request.delivery_status
      assert_equal AppstoreSDK::Models::Platform::APPLE, request.platform
      assert_not_equal AppstoreSDK::Models::PlayTime::UNDECLARED, request.play_time
    end

    def test_uses_override_status_when_provided
      request = builder.call(consumption_status: :not_consumed)

      assert_equal AppstoreSDK::Models::ConsumptionStatus::NOT_CONSUMED, request.consumption_status
    end

    def test_handles_missing_subscription
      request = builder_class.new(subscription: nil, transaction_payload: @transaction_payload).call

      assert_equal @transaction_payload[:app_account_token], request.app_account_token
      assert_equal AppstoreSDK::Models::AccountTenure::UNDECLARED, request.account_tenure
    end

    def test_marks_delivery_failure_for_refunded_subscription
      @subscription.update!(status: 'refunded')

      request = builder.call

      assert_equal AppstoreSDK::Models::ConsumptionStatus::NOT_CONSUMED, request.consumption_status
      assert_equal AppstoreSDK::Models::DeliveryStatus::DID_NOT_DELIVER_FOR_OTHER_REASON, request.delivery_status
    end

    def test_marks_partially_consumed_for_billing_retry
      @subscription.update!(status: 'billing_retry')

      request = builder.call

      assert_equal AppstoreSDK::Models::ConsumptionStatus::PARTIALLY_CONSUMED, request.consumption_status
    end

    private

    def builder
      builder_class.new(subscription: @subscription, transaction_payload: @transaction_payload)
    end

    def builder_class
      AppstoreWebhooks::ConsumptionRequestBuilder
    end
  end
end
