# frozen_string_literal: true

require 'test_helper'

class SyncSubscriptionJobTest < ActiveSupport::TestCase
  def setup
    @subscription = create_subscription(original_transaction_id: '10000000000002')
  end

  def test_calls_service_and_reload_subscription
    captured_kwargs = nil
    result = AppstoreWebhooks::RemoteSubscriptionSyncService::Result.new(
      status_response: nil,
      decoded_transactions: [],
      latest_transaction: nil
    )

    fake_service_class = Class.new do
      def initialize(subscription, result)
        @subscription = subscription
        @result = result
      end

      def call
        @subscription.update!(last_synced_at: Time.zone.parse('2024-01-01 00:00:00')) if @subscription
        @result
      end
    end

    AppstoreWebhooks::RemoteSubscriptionSyncService.stub(:new, ->(**kwargs) {
      captured_kwargs = kwargs
      fake_service_class.new(kwargs[:subscription], result)
    }) do
      travel_to(Time.zone.parse('2024-01-02 00:00:00')) do
        returned = AppstoreWebhooks::SyncSubscriptionJob.perform_now(subscription_id: @subscription.id)
        assert_equal result, returned
      end
    end

    assert_equal @subscription, captured_kwargs[:subscription]
    assert_equal '10000000000002', captured_kwargs[:original_transaction_id]
    assert_equal Time.zone.parse('2024-01-01 00:00:00'), @subscription.reload.last_synced_at
  end

  def test_logs_when_subscription_missing
    original_id = '10000000000009'
    result = AppstoreWebhooks::RemoteSubscriptionSyncService::Result.new(
      status_response: nil,
      decoded_transactions: [],
      latest_transaction: nil
    )

    logger = Minitest::Mock.new
    logger.expect(:info, nil, [String])

    service_stub = ->(**kwargs) do
      assert_nil kwargs[:subscription]
      assert_equal original_id, kwargs[:original_transaction_id]
      Struct.new(:result) do
        def call
          result
        end
      end.new(result)
    end

    Rails.stub(:logger, logger) do
      AppstoreWebhooks::RemoteSubscriptionSyncService.stub(:new, service_stub) do
        returned = AppstoreWebhooks::SyncSubscriptionJob.perform_now(original_transaction_id: original_id)
        assert_equal result, returned
      end
    end

    logger.verify
  end

  def test_logs_and_reraises_on_failure
    error = StandardError.new('boom')

    logger = Minitest::Mock.new
    logger.expect(:error, nil, [String])

    failing_service = Class.new do
      def initialize(error)
        @error = error
      end

      def call
        raise @error
      end
    end

    Rails.stub(:logger, logger) do
      AppstoreWebhooks::RemoteSubscriptionSyncService.stub(:new, ->(**_kwargs) { failing_service.new(error) }) do
        assert_raises(StandardError) do
          AppstoreWebhooks::SyncSubscriptionJob.perform_now(subscription_id: @subscription.id)
        end
      end
    end

    logger.verify
  end
end
