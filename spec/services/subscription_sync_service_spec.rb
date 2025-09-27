# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AppstoreWebhooks::SubscriptionSyncService do
  let(:user) do
    AppstoreWebhooks.configuration.user_class_constant.create!(
      app_account_token: SecureRandom.uuid,
      apple_uid: SecureRandom.uuid
    )
  end

  let(:subscription) do
    AppstoreWebhooks::Subscription.create!(
      user: user,
      original_transaction_id: SecureRandom.uuid,
      app_account_token: user.app_account_token,
      product_id: 'product.basic'
    )
  end

  def notification_for(type, subtype: nil)
    AppstoreWebhooks::Notification.create!(
      notification_uuid: SecureRandom.uuid,
      notification_type: type,
      subtype: subtype,
      processing_state: AppstoreWebhooks::Notification::STATES[:processing],
      app_account_token: subscription.app_account_token,
      raw_payload: {},
      transaction_payload: {},
      renewal_payload: {}
    )
  end

  describe '#call' do
    it 'activates the subscription and syncs attributes for SUBSCRIBED events' do
      payload = {
        original_transaction_id: subscription.original_transaction_id,
        product_id: 'product.premium',
        expires_date: (Time.current + 1.day).to_i * 1000,
        app_account_token: subscription.app_account_token,
        environment: 'Production'
      }

      service = described_class.new(
        notification: notification_for('SUBSCRIBED'),
        transaction_payload: payload,
        renewal_payload: {}
      )

      service.call(subscription)

      subscription.reload

      expect(subscription).to have_attributes(
        product_id: 'product.premium',
        status: 'active',
        environment: 'production'
      )
      expect(subscription.expires_at).to be_within(5.seconds).of(Time.current + 1.day)
      expect(subscription.last_synced_at).to be_within(5.seconds).of(Time.current)
    end

    it 'enters grace period when the notification reports a failed renewal with grace data' do
      payload = {
        original_transaction_id: subscription.original_transaction_id,
        grace_period_expires_date: (Time.current + 3.days).to_i * 1000
      }

      service = described_class.new(
        notification: notification_for('DID_FAIL_TO_RENEW'),
        transaction_payload: payload,
        renewal_payload: {}
      )

      service.call(subscription)

      expect(subscription.reload.status).to eq('grace')
    end

    it 'disables auto-renew when renewal status changes to AUTO_RENEW_DISABLED' do
      renewal_payload = {
        original_transaction_id: subscription.original_transaction_id,
        auto_renew_status: '1'
      }

      service = described_class.new(
        notification: notification_for('DID_CHANGE_RENEWAL_STATUS', subtype: 'AUTO_RENEW_DISABLED'),
        transaction_payload: {},
        renewal_payload: renewal_payload
      )

      service.call(subscription)

      subscription.reload

      expect(subscription.status).to eq('canceled')
      expect(subscription.auto_renew_status).to be(false)
    end
  end
end
