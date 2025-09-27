# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AppstoreWebhooks::NotifyMissingUserJob, type: :job do
  let(:notification) { create(:appstore_webhooks_notification) }
  let(:mailer_double) { instance_double(ActionMailer::MessageDelivery, deliver_now: true) }

  it 'delivers missing user email when notification exists' do
    allow(AppstoreWebhooks::NotificationMailer)
      .to receive(:missing_user)
      .with(notification, 'token-123')
      .and_return(mailer_double)

    described_class.perform_now(notification.id, 'token-123')

    expect(AppstoreWebhooks::NotificationMailer)
      .to have_received(:missing_user).with(notification, 'token-123')
    expect(mailer_double).to have_received(:deliver_now)
  end

  it 'returns silently when notification is missing' do
    allow(AppstoreWebhooks::NotificationMailer).to receive(:missing_user)

    expect do
      described_class.perform_now('non-existent-id', 'token-123')
    end.not_to raise_error

    expect(AppstoreWebhooks::NotificationMailer).not_to have_received(:missing_user)
  end
end
