# frozen_string_literal: true

require 'test_helper'

class SubscriptionSyncServiceTest < ActiveSupport::TestCase
  def setup
    @user = create_user
    @subscription = create_subscription(user: @user, product_id: 'product.basic')
  end

  def notification_for(type, subtype: nil)
    create_notification(
      subscription: @subscription,
      notification_type: type,
      subtype: subtype,
      processing_state: AppstoreWebhooks::Notification::STATES[:processing]
    )
  end

  def test_activates_subscription_and_syncs_attributes_for_subscribed
    payload = {
      original_transaction_id: @subscription.original_transaction_id,
      product_id: 'product.premium',
      expires_date: (Time.current + 1.day).to_i * 1000,
      app_account_token: @subscription.app_account_token,
      environment: 'Production'
    }

    renewal_payload = {
      original_transaction_id: @subscription.original_transaction_id,
      auto_renew_status: '1'
    }

    service = AppstoreWebhooks::SubscriptionSyncService.new(
      notification: notification_for('SUBSCRIBED'),
      transaction_payload: payload,
      renewal_payload: renewal_payload
    )

    travel_to Time.current do
      service.call(@subscription)
    end

    @subscription.reload
    assert_equal 'product.premium', @subscription.product_id
    assert_equal 'active', @subscription.status
    assert_equal 'production', @subscription.environment
    assert_equal true, @subscription.auto_renew_status
    assert_in_delta Time.current + 1.day, @subscription.expires_at, 5
    assert_in_delta Time.current, @subscription.last_synced_at, 5
  end

  def test_enters_grace_period_when_renewal_fails_with_grace_data
    payload = {
      original_transaction_id: @subscription.original_transaction_id,
      grace_period_expires_date: (Time.current + 3.days).to_i * 1000
    }

    service = AppstoreWebhooks::SubscriptionSyncService.new(
      notification: notification_for('DID_FAIL_TO_RENEW'),
      transaction_payload: payload,
      renewal_payload: {}
    )

    service.call(@subscription)

    assert_equal 'grace', @subscription.reload.status
  end

  def test_disables_auto_renew_when_status_changes
    renewal_payload = {
      original_transaction_id: @subscription.original_transaction_id,
      auto_renew_status: '1'
    }

    service = AppstoreWebhooks::SubscriptionSyncService.new(
      notification: notification_for('DID_CHANGE_RENEWAL_STATUS', subtype: 'AUTO_RENEW_DISABLED'),
      transaction_payload: {},
      renewal_payload: renewal_payload
    )

    service.call(@subscription)

    assert_equal 'canceled', @subscription.reload.status
    assert_equal false, @subscription.auto_renew_status
  end
end
