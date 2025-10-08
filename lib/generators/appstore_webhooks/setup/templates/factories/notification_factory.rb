# frozen_string_literal: true

FactoryBot.define do
  factory :appstore_webhooks_notification, class: "AppstoreWebhooks::Notification" do
    notification_uuid { SecureRandom.uuid }
    notification_type { "SUBSCRIBED" }
    subtype { nil }
    app_account_token { association(:subscription).app_account_token }
    processing_state { AppstoreWebhooks::Notification::STATES[:pending] }
    raw_payload { {} }
    transaction_payload { {} }
    renewal_payload { {} }
  end
end
