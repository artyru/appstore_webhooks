# frozen_string_literal: true

require "test_helper"

class RespondToConsumptionRequestJobTest < ActiveSupport::TestCase
  def setup
    @user = create_user
    @transaction_payload = {
      "original_transaction_id" => "10000000000001",
      "transaction_id" => "10000000000001",
      "app_account_token" => @user.app_account_token
    }
    @subscription = create_subscription(
      user: @user,
      original_transaction_id: @transaction_payload["original_transaction_id"],
      app_account_token: @user.app_account_token,
      status: "active"
    )
    @notification = create_notification(
      notification_type: "CONSUMPTION_REQUEST",
      transaction_payload: @transaction_payload,
      processing_state: "pending",
      subscription: @subscription,
      app_account_token: @user.app_account_token
    )

    @original_environment = AppstoreSDK.configuration.environment
    @original_bundle_id = AppstoreSDK.configuration.bundle_id
    AppstoreSDK.configuration.environment = :local_testing
    AppstoreSDK.configuration.bundle_id = "team.memriq.test"
  end

  def teardown
    AppstoreSDK.configuration.environment = @original_environment
    AppstoreSDK.configuration.bundle_id = @original_bundle_id
    super
  end

  def test_fetches_consumption_info_and_marks_notification_processed
    captured_kwargs = nil
    service = Minitest::Mock.new
    service.expect(:call, true)

    AppstoreWebhooks::ConsumptionInformationService.stub(:new, lambda { |**kwargs|
      captured_kwargs = kwargs
      service
    }) do
      AppstoreWebhooks::RespondToConsumptionRequestJob.perform_now(@notification.id)
    end

    assert_equal @subscription, captured_kwargs[:subscription]
    assert_equal @transaction_payload["original_transaction_id"],
                 captured_kwargs[:transaction_payload][:original_transaction_id]

    assert_equal "processed", @notification.reload.processing_state
    assert_nil @notification.processing_error
    service.verify
  end

  def test_marks_notification_failed_when_service_raises
    AppstoreWebhooks::ConsumptionInformationService.stub(:new, ->(**_kwargs) { raise StandardError, "boom" }) do
      assert_raises(StandardError) do
        AppstoreWebhooks::RespondToConsumptionRequestJob.perform_now(@notification.id)
      end
    end

    @notification.reload
    assert_equal "failed", @notification.processing_state
    assert_equal "boom", @notification.processing_error
  end
end
