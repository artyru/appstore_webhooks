# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AppstoreWebhooks::SubscriptionEvent, type: :model do
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
      product_id: 'product.1'
    )
  end

  let(:notification) do
    AppstoreWebhooks::Notification.create!(
      notification_uuid: SecureRandom.uuid,
      notification_type: 'SUBSCRIBED',
      processing_state: AppstoreWebhooks::Notification::STATES[:processing],
      app_account_token: subscription.app_account_token,
      raw_payload: {},
      transaction_payload: {},
      renewal_payload: {}
    )
  end

  it 'requires next_status and effective_at' do
    event = described_class.new(subscription: subscription,
                                webhook_notification: notification,
                                previous_status: 'active')

    expect(event).not_to be_valid
    expect(event.errors[:next_status]).to include("can't be blank")
    expect(event.errors[:effective_at]).to include("can't be blank")
  end

  it 'persists when required attributes are present' do
    event = described_class.new(
      subscription: subscription,
      webhook_notification: notification,
      previous_status: 'active',
      next_status: 'expired',
      effective_at: Time.current,
      metadata: { foo: 'bar' }
    )

    expect { event.save! }.to change(described_class, :count).by(1)
    expect(event.metadata).to include('foo' => 'bar')
  end
end
