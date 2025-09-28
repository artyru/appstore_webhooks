# frozen_string_literal: true

FactoryBot.define do
  factory :subscription, class: 'AppstoreWebhooks::Subscription' do
    association :user
    original_transaction_id { SecureRandom.uuid }
    app_account_token { user.app_account_token || SecureRandom.uuid }
    product_id { 'pro.weekly' }
    status { :active }
    environment { 'sandbox' }
    expires_at { 1.day.from_now }
    grace_period_expires_at { nil }
    auto_renew_status { true }
  end
end
