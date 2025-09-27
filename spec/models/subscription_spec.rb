# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AppstoreWebhooks::Subscription, type: :model do
  it 'validates presence of original_transaction_id' do
    subscription = described_class.new(original_transaction_id: nil)
    subscription.validate
    expect(subscription.errors[:original_transaction_id]).to be_present
  end
end
