# frozen_string_literal: true

require 'test_helper'

class ProcessNotificationWorkerTest < ActiveSupport::TestCase
  SimplePayload = Struct.new(:data) do
    def to_h
      data
    end
  end

  SimpleVerifier = Struct.new(:transaction_payload, :renewal_payload) do
    def verify_and_decode_signed_transaction(_token)
      SimplePayload.new(transaction_payload)
    end

    def verify_and_decode_renewal_info(_token)
      SimplePayload.new(renewal_payload)
    end
  end

  def setup
    super
    ActiveJob::Base.queue_adapter = :test
    clear_enqueued_jobs

    @bundle_id = 'team.memriq.test'
    @app_account_token = SecureRandom.uuid
    @notification_uuid = SecureRandom.uuid
    @base_transaction = build_transaction_payload(
      'bundleId' => @bundle_id,
      'appAccountToken' => @app_account_token,
      'originalTransactionId' => '10000000000001',
      'transactionId' => '10000000000001',
      'productId' => 'product.basic'
    )

    @original_environment = AppstoreSDK.configuration.environment
    @original_bundle_id = AppstoreSDK.configuration.bundle_id
    AppstoreSDK.configuration.environment = :local_testing
    AppstoreSDK.configuration.bundle_id = @bundle_id
  end

  def teardown
    clear_enqueued_jobs
    AppstoreSDK.configuration.environment = @original_environment
    AppstoreSDK.configuration.bundle_id = @original_bundle_id
    super
  end

  def test_creates_subscription_and_marks_notification_processed_for_subscribed
    user = create_user(app_account_token: @app_account_token)
    renewal_payload = build_renewal_payload(
      'originalTransactionId' => @base_transaction['originalTransactionId'],
      'autoRenewStatus' => '1'
    )

    payload_hash = build_worker_payload(
      notification_type: 'SUBSCRIBED',
      transaction_payload: @base_transaction,
      renewal_payload: renewal_payload
    )

    assert_difference -> { AppstoreWebhooks::Notification.count }, 1 do
      assert_difference -> { AppstoreWebhooks::Subscription.count }, 1 do
        assert_difference -> { AppstoreWebhooks::SubscriptionEvent.count }, 1 do
          perform_worker(payload_hash,
                         transaction_payload: @base_transaction,
                         renewal_payload: renewal_payload)
        end
      end
    end

    subscription = AppstoreWebhooks::Subscription.find_by(original_transaction_id: @base_transaction['originalTransactionId'])
    assert subscription.present?
    assert_equal 'active', subscription.status
    assert_equal true, subscription.auto_renew_status

    notification = AppstoreWebhooks::Notification.find_by(notification_uuid: @notification_uuid)
    assert_equal 'processed', notification.processing_state
    assert_equal subscription, notification.subscription
  end

  def test_updates_subscription_when_auto_renew_disabled
    user = create_user(app_account_token: @app_account_token)
    subscription = create_subscription(
      user: user,
      original_transaction_id: @base_transaction['originalTransactionId'],
      app_account_token: @app_account_token,
      product_id: @base_transaction['productId'],
      status: 'active'
    )

    transaction_payload = @base_transaction.merge('expiresDate' => (2.hours.from_now.to_i * 1000))
    renewal_payload = build_renewal_payload(
      'originalTransactionId' => @base_transaction['originalTransactionId'],
      'autoRenewStatus' => '0'
    )

    payload_hash = build_worker_payload(
      notification_type: 'DID_CHANGE_RENEWAL_STATUS',
      subtype: 'AUTO_RENEW_DISABLED',
      transaction_payload: transaction_payload,
      renewal_payload: renewal_payload
    )

    assert_difference -> { AppstoreWebhooks::SubscriptionEvent.count }, 1 do
      perform_worker(payload_hash,
                     transaction_payload: transaction_payload,
                     renewal_payload: renewal_payload)
    end

    subscription.reload
    assert_equal 'canceled', subscription.status
    assert_equal false, subscription.auto_renew_status

    notification = AppstoreWebhooks::Notification.find_by(notification_uuid: @notification_uuid)
    assert_equal 'processed', notification.processing_state
  end

  def test_marks_notification_failed_and_enqueues_alert_when_user_missing
    create_user(app_account_token: @app_account_token)&.destroy

    payload_hash = build_worker_payload(
      notification_type: 'SUBSCRIBED',
      transaction_payload: @base_transaction
    )

    assert_difference -> { AppstoreWebhooks::Notification.count }, 1 do
      assert_no_difference -> { AppstoreWebhooks::Subscription.count } do
        assert_enqueued_with(job: AppstoreWebhooks::NotifyMissingUserJob) do
          perform_worker(payload_hash, transaction_payload: @base_transaction, renewal_payload: {})
        end
      end
    end

    notification = AppstoreWebhooks::Notification.find_by(notification_uuid: @notification_uuid)
    assert_equal 'failed', notification.processing_state
    assert_match(/User not found/, notification.processing_error)
  end

  def test_enqueues_consumption_response_for_consumption_request
    payload_hash = build_worker_payload(
      notification_type: 'CONSUMPTION_REQUEST',
      transaction_payload: @base_transaction
    )

    assert_difference -> { AppstoreWebhooks::Notification.count }, 1 do
      assert_enqueued_jobs 1 do
        perform_worker(payload_hash, transaction_payload: @base_transaction, renewal_payload: {})
      end
    end

    notification = AppstoreWebhooks::Notification.find_by(notification_uuid: @notification_uuid)
    assert_equal 'processing', notification.processing_state
    assert_enqueued_with(job: AppstoreWebhooks::RespondToConsumptionRequestJob, args: [notification.id])
  end

  def test_marks_notification_processed_when_transaction_data_missing
    payload_hash = {
      'notificationType' => 'DID_RENEW',
      'notificationUUID' => @notification_uuid,
      'data' => { 'environment' => 'LocalTesting' },
      'version' => '2.0',
      'signedDate' => (Time.current.to_i * 1000)
    }

    assert_difference -> { AppstoreWebhooks::Notification.count }, 1 do
      assert_no_difference -> { AppstoreWebhooks::Subscription.count } do
        perform_worker(payload_hash, transaction_payload: {}, renewal_payload: {})
      end
    end

    notification = AppstoreWebhooks::Notification.find_by(notification_uuid: @notification_uuid)
    assert_equal 'processed', notification.processing_state
    assert_nil notification.subscription
  end

  def test_marks_notification_failed_when_sync_service_raises
    user = create_user(app_account_token: @app_account_token)
    create_subscription(
      user: user,
      original_transaction_id: @base_transaction['originalTransactionId'],
      app_account_token: @app_account_token,
      product_id: @base_transaction['productId'],
      status: 'active'
    )

    payload_hash = build_worker_payload(
      notification_type: 'SUBSCRIBED',
      transaction_payload: @base_transaction
    )

    AppstoreWebhooks::SubscriptionSyncService.stub(:new, ->(*) { raise StandardError, 'sync-failed' }) do
      error = assert_raises(StandardError) do
        perform_worker(payload_hash, transaction_payload: @base_transaction, renewal_payload: {})
      end
      assert_equal 'sync-failed', error.message
    end

    notification = AppstoreWebhooks::Notification.find_by(notification_uuid: @notification_uuid)
    assert_equal 'failed', notification.processing_state
    assert_equal 'sync-failed', notification.processing_error
  end

  private

  def build_worker_payload(notification_type:, transaction_payload:, renewal_payload: {}, subtype: nil)
    data = { 'environment' => 'LocalTesting' }
    data['signedTransactionInfo'] = 'stub-transaction' if transaction_payload.present?
    data['signedRenewalInfo'] = 'stub-renewal' if renewal_payload.present?

    {
      'notificationType' => notification_type,
      'subtype' => subtype,
      'notificationUUID' => @notification_uuid,
      'data' => data,
      'version' => '2.0',
      'signedDate' => (Time.current.to_i * 1000)
    }.compact
  end

  def perform_worker(payload_hash, transaction_payload:, renewal_payload: {})
    verifier = SimpleVerifier.new(transaction_payload || {}, renewal_payload || {})
    worker = AppstoreWebhooks::ProcessNotificationWorker.new

    worker.stub(:build_signed_data_verifier, verifier) do
      worker.perform(payload_hash)
    end
  end

  def assert_no_difference(expression, &block)
    assert_difference(expression, 0, &block)
  end
end
