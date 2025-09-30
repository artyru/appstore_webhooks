# frozen_string_literal: true

require 'test_helper'
require 'rake'

class RetryFailedNotificationsTaskTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  TASK_NAME = 'appstore_webhooks:notifications:retry_failed'

  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?(TASK_NAME)
    Rake::Task[TASK_NAME].reenable
    clear_enqueued_jobs
  end

  teardown do
    clear_enqueued_jobs
  end

  def test_requeues_failed_notifications
    notification = create_notification(
      processing_state: AppstoreWebhooks::Notification::STATES[:failed],
      processing_error: 'boom',
      raw_payload: { 'signedPayload' => 'token' }
    )

    assert_enqueued_with(job: AppstoreWebhooks::ProcessNotificationWorker) do
      Rake::Task[TASK_NAME].invoke
    end

    notification.reload
    assert_equal AppstoreWebhooks::Notification::STATES[:pending], notification.processing_state
    assert_nil notification.processing_error
  end

  def test_limit_environment_variable_restricts_scope
    notifications = Array.new(3) do
      create_notification(
        processing_state: AppstoreWebhooks::Notification::STATES[:failed],
        raw_payload: { 'signedPayload' => SecureRandom.uuid }
      )
    end

    ENV['LIMIT'] = '2'

    Rake::Task[TASK_NAME].invoke

    processed = notifications.select { |n| n.reload.processing_state == AppstoreWebhooks::Notification::STATES[:pending] }
    assert_equal 2, processed.size
  ensure
    ENV.delete('LIMIT')
  end

  def test_skips_notifications_without_raw_payload
    notification = create_notification(
      processing_state: AppstoreWebhooks::Notification::STATES[:failed],
      raw_payload: {}
    )

    assert_no_enqueued_jobs do
      Rake::Task[TASK_NAME].invoke
    end

    assert_equal AppstoreWebhooks::Notification::STATES[:failed], notification.reload.processing_state
  end
end
