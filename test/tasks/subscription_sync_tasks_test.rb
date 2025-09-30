# frozen_string_literal: true

require 'test_helper'
require 'rake'

class SubscriptionSyncTasksTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  SYNC_TASK = 'appstore_webhooks:subscriptions:sync'
  SYNC_STALE_TASK = 'appstore_webhooks:subscriptions:sync_stale'

  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?(SYNC_TASK)
    Rake::Task[SYNC_TASK].reenable
    Rake::Task[SYNC_STALE_TASK].reenable
    clear_enqueued_jobs
  end

  teardown do
    clear_enqueued_jobs
    %w[ASYNC LIMIT STALE_AFTER_MINUTES BATCH_SIZE ORIGINAL_TRANSACTION_ID SILENT].each { |key| ENV.delete(key) }
  end

  def test_sync_runs_service_synchronously_by_default
    subscription = create_subscription(original_transaction_id: '10000000000021', last_synced_at: nil)
    result = AppstoreWebhooks::RemoteSubscriptionSyncService::Result.new(
      status_response: nil,
      decoded_transactions: [],
      latest_transaction: nil
    )

    captured_subscription = nil

    fake_service_class = Class.new do
      def initialize(subscription, result)
        @subscription = subscription
        @result = result
      end

      def call
        @subscription.update!(last_synced_at: Time.zone.parse('2024-01-03 00:00:00')) if @subscription
        @result
      end
    end

    AppstoreWebhooks::RemoteSubscriptionSyncService.stub(:new, ->(**kwargs) {
      captured_subscription = kwargs[:subscription]
      fake_service_class.new(kwargs[:subscription], result)
    }) do
      Rake::Task[SYNC_TASK].invoke(subscription.original_transaction_id)
    end

    assert_equal subscription, captured_subscription
    assert_equal Time.zone.parse('2024-01-03 00:00:00'), subscription.reload.last_synced_at
    assert_equal 0, enqueued_jobs.size
  ensure
    Rake::Task[SYNC_TASK].reenable
  end

  def test_sync_requires_original_transaction_id
    assert_raises(ArgumentError) do
      Rake::Task[SYNC_TASK].invoke
    end
  ensure
    Rake::Task[SYNC_TASK].reenable
  end

  def test_sync_stale_enqueues_only_outdated_subscriptions
    stale = create_subscription(last_synced_at: 3.days.ago, original_transaction_id: '10000000001000')
    recent = create_subscription(last_synced_at: 10.minutes.ago, original_transaction_id: '10000000001001')
    never = create_subscription(last_synced_at: nil, original_transaction_id: '10000000001002')

    ENV['ASYNC'] = 'true'
    ENV['LIMIT'] = '2'
    ENV['STALE_AFTER_MINUTES'] = '60'
    ENV['SILENT'] = 'true'

    assert_enqueued_jobs 2 do
      Rake::Task[SYNC_STALE_TASK].invoke
    end

    job_args = enqueued_jobs.map { |job| job[:args].first }
    subscription_ids = job_args.map { |args| args['subscription_id'] }.compact

    assert_includes subscription_ids, stale.id
    assert_includes subscription_ids, never.id
    refute_includes subscription_ids, recent.id
  ensure
    Rake::Task[SYNC_STALE_TASK].reenable
  end
end
