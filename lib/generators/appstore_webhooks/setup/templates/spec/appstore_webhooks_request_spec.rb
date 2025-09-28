# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'AppstoreWebhooks notifications', type: :request do
  include ActiveJob::TestHelper

  # Adjust this path to match how you mount the engine in your application.
  let(:endpoint_path) { '/api/v1/appstore_webhooks' }
  let(:user_token) { SecureRandom.uuid }

  # Update this factory to match your application's user model.
  let!(:user) { create(AppstoreWebhooks.configuration.user_class.underscore.to_sym, app_account_token: user_token) }

  let(:transaction_payload) do
    build(:apple_transaction_payload,
          appAccountToken: user_token,
          originalTransactionId: SecureRandom.uuid,
          transactionId: SecureRandom.uuid)
  end

  let(:renewal_payload) do
    build(:apple_renewal_payload,
          originalTransactionId: transaction_payload['originalTransactionId'],
          productId: transaction_payload['productId'])
  end

  let(:notification_payload) do
    {
      'notificationType' => 'SUBSCRIBED',
      'notificationUUID' => SecureRandom.uuid,
      'data' => {
        'environment' => transaction_payload['environment'],
        'bundleId' => transaction_payload['bundleId'],
        'signedTransactionInfo' => encode_apple_jws(transaction_payload),
        'signedRenewalInfo' => encode_apple_jws(renewal_payload),
        'status' => 1
      },
      'version' => '2.0',
      'signedDate' => (Time.current.to_i * 1000)
    }
  end

  let(:request_body) { { signedPayload: encode_apple_jws(notification_payload) } }

  before do
    ActiveJob::Base.queue_adapter = :test

    AppstoreSDK.configure do |config|
      config.environment = :local_testing
      config.bundle_id = transaction_payload['bundleId']
    end

    allow(AppstoreWebhooks::ProcessNotificationWorker).to receive(:perform_now).and_call_original
  end

  after do
    ActiveJob::Base.queue_adapter = :inline
  end

  it 'persists the notification and triggers processing' do
    expect do
      post endpoint_path, params: request_body, as: :json
    end.to change(AppstoreWebhooks::Notification, :count).by(1)

    expect(response).to have_http_status(:ok)
    expect(AppstoreWebhooks::ProcessNotificationWorker).to have_received(:perform_now)
  end
end
