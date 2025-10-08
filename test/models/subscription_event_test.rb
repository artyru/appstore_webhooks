# frozen_string_literal: true

require "test_helper"

class SubscriptionEventTest < ActiveSupport::TestCase
  def setup
    @user = create_user
    @subscription = create_subscription(user: @user)
    @notification = create_notification(subscription: @subscription,
                                        processing_state: AppstoreWebhooks::Notification::STATES[:processing])
  end

  def test_validations_require_next_status_and_effective_at
    event = AppstoreWebhooks::SubscriptionEvent.new(
      subscription: @subscription,
      webhook_notification: @notification,
      previous_status: "active"
    )

    assert_not event.valid?
    assert_includes event.errors[:next_status], "can't be blank"
    assert_includes event.errors[:effective_at], "can't be blank"
  end

  def test_persists_with_required_attributes
    event = AppstoreWebhooks::SubscriptionEvent.new(
      subscription: @subscription,
      webhook_notification: @notification,
      previous_status: "active",
      next_status: "expired",
      effective_at: Time.current,
      metadata: { "foo" => "bar" }
    )

    assert_difference -> { AppstoreWebhooks::SubscriptionEvent.count }, 1 do
      event.save!
    end

    assert_equal "bar", event.reload.metadata["foo"]
  end
end
