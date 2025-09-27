# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AppstoreWebhooks::ProcessNotificationWorker, type: :worker do
  include ActiveJob::TestHelper
  include AppleWebhookPayloadHelper

  subject(:perform_worker) { described_class.new.perform(payload_hash) }

  let(:bundle_id) { 'team.memriq.test' }
  let(:app_account_token) { SecureRandom.uuid }
  let(:notification_uuid) { SecureRandom.uuid }
  let(:base_transaction) do
    build(:apple_transaction_payload,
          bundleId: bundle_id,
          appAccountToken: app_account_token,
          originalTransactionId: '10000000000001',
          transactionId: '10000000000001')
  end

  before do
    ActiveJob::Base.queue_adapter = :test
    @original_environment = AppstoreSDK.configuration.environment
    @original_bundle_id = AppstoreSDK.configuration.bundle_id

    AppstoreSDK.configuration.environment = :local_testing
    AppstoreSDK.configuration.bundle_id = bundle_id
  end

  after do
    clear_enqueued_jobs
    AppstoreSDK.configuration.environment = @original_environment
    AppstoreSDK.configuration.bundle_id = @original_bundle_id
  end

  describe 'subscription lifecycle updates' do
    let!(:user) { create(:user, :with_apple_uid, app_account_token: app_account_token) }

    context 'when receiving SUBSCRIBED notification' do
      let(:payload_hash) do
        build_payload(
          notification_type: 'SUBSCRIBED',
          transaction_payload: base_transaction,
          renewal_payload: build(:apple_renewal_payload, originalTransactionId: base_transaction['originalTransactionId'])
        )
      end

      it 'creates and activates subscription' do
        expect { perform_worker }
          .to change(AppstoreWebhooks::Notification, :count).by(1)
          .and change(AppstoreWebhooks::Subscription, :count).by(1)
          .and change(AppstoreWebhooks::SubscriptionEvent, :count).by(1)

        subscription = AppstoreWebhooks::Subscription.find_by(original_transaction_id: base_transaction['originalTransactionId'])
        expect(subscription).to be_present
        expect(subscription).to be_active
        expect(subscription.auto_renew_status).to eq(true)

        notification = AppstoreWebhooks::Notification.find_by(notification_uuid: notification_uuid)
        expect(notification.processing_state).to eq('processed')
        expect(notification.subscription).to eq(subscription)
      end
    end

    context 'when receiving DID_CHANGE_RENEWAL_STATUS disabling auto renew' do
      let!(:subscription) do
        create(:subscription,
               user: user,
               original_transaction_id: base_transaction['originalTransactionId'],
               app_account_token: app_account_token,
               product_id: base_transaction['productId'],
               status: :active)
      end

      let(:payload_hash) do
        build_payload(
          notification_type: 'DID_CHANGE_RENEWAL_STATUS',
          subtype: 'AUTO_RENEW_DISABLED',
          transaction_payload: base_transaction.merge('expiresDate' => (2.hours.from_now.to_i * 1000)),
          renewal_payload: build(:apple_renewal_payload,
                                  :auto_renew_disabled,
                                  originalTransactionId: base_transaction['originalTransactionId'])
        )
      end

      it 'switches subscription to canceled and updates auto renew flag' do
        expect { perform_worker }
          .to change { subscription.reload.status }.from('active').to('canceled')
          .and change(AppstoreWebhooks::SubscriptionEvent, :count).by(1)

        expect(subscription.reload.auto_renew_status).to eq(false)

        notification = AppstoreWebhooks::Notification.find_by(notification_uuid: notification_uuid)
        expect(notification.processing_state).to eq('processed')
      end
    end

    context 'when user is unknown' do
      let(:payload_hash) do
        build_payload(
          notification_type: 'SUBSCRIBED',
          transaction_payload: base_transaction
        )
      end

      before { user.destroy }

      it 'marks notification failed and notifies team' do
        expect { perform_worker }
          .to change(AppstoreWebhooks::Notification, :count).by(1)
          .and change(AppstoreWebhooks::Subscription, :count).by(0)

        notification = AppstoreWebhooks::Notification.find_by(notification_uuid: notification_uuid)
        expect(notification.processing_state).to eq('failed')
        expect(notification.processing_error).to match(/User not found/)
        expect(AppstoreWebhooks::NotifyMissingUserJob)
          .to have_been_enqueued.with(notification.id, app_account_token)
      end
    end
  end

  describe 'consumption request notifications' do
    let(:payload_hash) do
      build_payload(
        notification_type: 'CONSUMPTION_REQUEST',
        transaction_payload: base_transaction
      )
    end

    it 'enqueues consumption response job' do
      expect { perform_worker }
        .to change(AppstoreWebhooks::Notification, :count).by(1)

      notification = AppstoreWebhooks::Notification.find_by(notification_uuid: notification_uuid)

      expect(AppstoreWebhooks::RespondToConsumptionRequestJob)
        .to have_been_enqueued.with(notification.id)
      expect(notification.processing_state).to eq('processing')
    end
  end

  describe 'notifications without transaction data' do
    let(:payload_hash) do
      {
        'notificationType' => 'DID_RENEW',
        'notificationUUID' => notification_uuid,
        'data' => {
          'environment' => 'LocalTesting'
        },
        'version' => '2.0',
        'signedDate' => (Time.current.to_i * 1000)
      }
    end

    it 'marks notification processed without creating a subscription' do
      expect { perform_worker }
        .to change(AppstoreWebhooks::Notification, :count).by(1)
        .and change(AppstoreWebhooks::Subscription, :count).by(0)

      notification = AppstoreWebhooks::Notification.find_by(notification_uuid: notification_uuid)
      expect(notification.processing_state).to eq('processed')
      expect(notification.subscription).to be_nil
    end
  end

  describe 'error handling' do
    let!(:user) { create(:user, :with_apple_uid, app_account_token: app_account_token) }

    let(:payload_hash) do
      build_payload(
        notification_type: 'SUBSCRIBED',
        transaction_payload: base_transaction,
        renewal_payload: {}
      )
    end

    before do
      allow(AppstoreWebhooks::SubscriptionSyncService)
        .to receive(:new)
        .and_raise(StandardError, 'sync-failed')
    end

    it 'marks notification failed and re-raises the error' do
      expect { perform_worker }.to raise_error(StandardError, 'sync-failed')

      notification = AppstoreWebhooks::Notification.find_by(notification_uuid: notification_uuid)
      expect(notification.processing_state).to eq('failed')
      expect(notification.processing_error).to eq('sync-failed')
    end
  end

  def build_payload(notification_type:, transaction_payload:, renewal_payload: {}, subtype: nil)
    data = { 'environment' => 'LocalTesting' }
    data['signedTransactionInfo'] = encode_apple_jws(transaction_payload) if transaction_payload.present?
    data['signedRenewalInfo'] = encode_apple_jws(renewal_payload) if renewal_payload.present?

    {
      'notificationType' => notification_type,
      'subtype' => subtype,
      'notificationUUID' => notification_uuid,
      'data' => data,
      'version' => '2.0',
      'signedDate' => (Time.current.to_i * 1000)
    }.compact
  end
end
