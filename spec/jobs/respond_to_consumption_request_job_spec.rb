# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AppstoreWebhooks::RespondToConsumptionRequestJob, type: :job do
  include ActiveJob::TestHelper

  let(:user) { create(:user, :with_apple_uid) }
  let(:transaction_payload) do
    build(:apple_transaction_payload, :normalized,
          originalTransactionId: '10000000000001',
          transactionId: '10000000000001',
          appAccountToken: user.app_account_token)
  end
  let(:notification) do
    create(:appstore_webhooks_notification,
           notification_type: 'CONSUMPTION_REQUEST',
           transaction_payload: transaction_payload,
           processing_state: 'pending')
  end
  let!(:subscription) do
    create(:subscription,
           user: user,
           original_transaction_id: transaction_payload['original_transaction_id'],
           app_account_token: user.app_account_token,
           status: :active)
  end

  before do
    @original_environment = AppstoreSDK.configuration.environment
    @original_bundle_id = AppstoreSDK.configuration.bundle_id
    AppstoreSDK.configuration.environment = :local_testing
    AppstoreSDK.configuration.bundle_id = 'team.memriq.test'
  end

  after do
    AppstoreSDK.configuration.environment = @original_environment
    AppstoreSDK.configuration.bundle_id = @original_bundle_id
  end

  it 'fetches consumption info and marks the notification processed' do
    service = instance_double(AppstoreWebhooks::ConsumptionInformationService, call: true)
    expect(AppstoreWebhooks::ConsumptionInformationService).to receive(:new)
      .with(transaction_payload: hash_including('original_transaction_id' => transaction_payload['original_transaction_id']),
            subscription: subscription)
      .and_return(service)

    described_class.perform_now(notification.id)

    expect(notification.reload.processing_state).to eq('processed')
    expect(notification.processing_error).to be_nil
  end

  context 'when service raises error' do
    it 'marks notification as failed and re-raises' do
      allow(AppstoreWebhooks::ConsumptionInformationService).to receive(:new).and_raise(StandardError, 'boom')

      expect { described_class.perform_now(notification.id) }.to raise_error(StandardError, 'boom')
      expect(notification.reload.processing_state).to eq('failed')
      expect(notification.processing_error).to eq('boom')
    end
  end
end
