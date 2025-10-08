# frozen_string_literal: true

require "test_helper"

class SubscriptionTest < ActiveSupport::TestCase
  def test_requires_original_transaction_id
    user = create_user
    subscription = AppstoreWebhooks::Subscription.new(
      user: user,
      original_transaction_id: nil,
      app_account_token: user.app_account_token,
      product_id: "product.basic"
    )

    assert_not subscription.valid?
    assert_includes subscription.errors[:original_transaction_id], "can't be blank"
  end

  def test_requires_expires_at
    user = create_user
    subscription = AppstoreWebhooks::Subscription.new(
      user: user,
      original_transaction_id: SecureRandom.uuid,
      app_account_token: user.app_account_token,
      product_id: "product.basic",
      status: "active",
      environment: "sandbox"
    )

    assert_not subscription.valid?
    assert_includes subscription.errors[:expires_at], "can't be blank"
  end

  def test_active_returns_true_when_subscription_active_and_not_expired
    subscription = create_subscription(expires_at: 5.minutes.from_now)

    assert subscription.active?
  end

  def test_active_returns_false_when_subscription_expired
    subscription = create_subscription(expires_at: 5.minutes.ago)

    assert_not subscription.active?
  end

  def test_active_returns_false_when_status_not_active
    subscription = create_subscription(status: "canceled", expires_at: 1.hour.from_now)

    assert_not subscription.active?
  end

  def test_entitlement_active_returns_true_for_active_subscription
    subscription = create_subscription(status: "active", expires_at: 30.minutes.from_now)

    assert subscription.entitlement_active?
  end

  def test_entitlement_active_returns_true_during_grace_period
    subscription = create_subscription(
      status: "grace",
      expires_at: 1.hour.ago,
      grace_period_expires_at: 1.hour.from_now
    )

    assert subscription.entitlement_active?
  end

  def test_entitlement_active_returns_false_when_grace_period_over
    subscription = create_subscription(
      status: "grace",
      expires_at: 2.hours.ago,
      grace_period_expires_at: 5.minutes.ago
    )

    assert_not subscription.entitlement_active?
  end

  def test_entitlement_active_returns_true_when_canceled_but_still_valid
    subscription = create_subscription(status: "canceled", expires_at: 45.minutes.from_now)

    assert subscription.entitlement_active?
  end

  def test_entitlement_active_returns_false_when_canceled_and_expired
    subscription = create_subscription(
      status: "canceled",
      expires_at: 30.minutes.ago,
      grace_period_expires_at: 1.day.from_now
    )

    assert_not subscription.entitlement_active?
  end

  def test_sync_from_transaction_normalizes_epoch_timestamps_to_time_zone
    Time.use_zone("Pacific Time (US & Canada)") do
      subscription = create_subscription(expires_at: 1.hour.from_now)
      millis = (Time.current + 2.hours).to_i * 1000
      payload = {
        "expiresDate" => millis,
        "appAccountToken" => subscription.app_account_token,
        "productId" => subscription.product_id,
        "originalTransactionId" => subscription.original_transaction_id,
        "environment" => "Sandbox"
      }

      subscription.sync_from_transaction(payload: payload)
      expected = Time.zone.at(millis / 1000.0)

      assert_in_delta expected, subscription.reload.expires_at, 0.5
      assert_instance_of ActiveSupport::TimeWithZone, subscription.expires_at
    end
  end
end
