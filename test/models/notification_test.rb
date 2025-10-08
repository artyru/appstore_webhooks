# frozen_string_literal: true

require "test_helper"

class NotificationTest < ActiveSupport::TestCase
  def setup
    @subscription = create_subscription
  end

  def test_requires_notification_uuid
    notification = AppstoreWebhooks::Notification.new(
      notification_type: "SUBSCRIBED",
      app_account_token: @subscription.app_account_token,
      processing_state: AppstoreWebhooks::Notification::STATES[:pending],
      raw_payload: {},
      transaction_payload: {},
      renewal_payload: {}
    )

    assert_not notification.valid?
    assert_includes notification.errors[:notification_uuid], "can't be blank"
  end

  def test_enforces_notification_uuid_uniqueness
    uuid = SecureRandom.uuid
    create_notification(notification_uuid: uuid, subscription: @subscription)

    duplicate = AppstoreWebhooks::Notification.new(
      notification_uuid: uuid,
      notification_type: "SUBSCRIBED",
      app_account_token: @subscription.app_account_token,
      processing_state: AppstoreWebhooks::Notification::STATES[:pending],
      raw_payload: {},
      transaction_payload: {},
      renewal_payload: {}
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:notification_uuid], "has already been taken"
  end

  def test_unprocessed_scope_returns_pending_notifications
    pending_notification = create_notification(
      subscription: @subscription,
      processing_state: AppstoreWebhooks::Notification::STATES[:pending]
    )
    create_notification(
      subscription: @subscription,
      processing_state: AppstoreWebhooks::Notification::STATES[:processed]
    )

    assert_equal [pending_notification], AppstoreWebhooks::Notification.unprocessed.to_a
  end
end
