# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AppstoreWebhooks::Notification, type: :model do
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

  def build_notification(attrs = {})
    described_class.new({
      notification_uuid: SecureRandom.uuid,
      notification_type: 'SUBSCRIBED',
      app_account_token: subscription.app_account_token,
      processing_state: described_class::STATES[:pending],
      raw_payload: {},
      transaction_payload: {},
      renewal_payload: {}
    }.merge(attrs))
  end

  it 'validates presence of notification_uuid' do
    notification = build_notification(notification_uuid: nil)

    expect(notification).not_to be_valid
    expect(notification.errors[:notification_uuid]).to include("can't be blank")
  end

  it 'enforces uniqueness of notification_uuid' do
    uuid = SecureRandom.uuid
    build_notification(notification_uuid: uuid).save!

    duplicate = build_notification(notification_uuid: uuid)

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:notification_uuid]).to include('has already been taken')
  end

  it 'exposes the unprocessed scope' do
    pending_notification = build_notification(processing_state: described_class::STATES[:pending])
    processed_notification = build_notification(processing_state: described_class::STATES[:processed])

    pending_notification.save!
    processed_notification.save!

    expect(described_class.unprocessed).to contain_exactly(pending_notification)
  end
end
