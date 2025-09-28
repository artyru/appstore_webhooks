# frozen_string_literal: true

FactoryBot.define do
  factory :appstore_webhooks_subscription_event, class: 'AppstoreWebhooks::SubscriptionEvent' do
    association :subscription
    association :webhook_notification, factory: :appstore_webhooks_notification
    previous_status { 'active' }
    next_status { 'canceled' }
    effective_at { Time.current }
    metadata { {} }
  end
end
