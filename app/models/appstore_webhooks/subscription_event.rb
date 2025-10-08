# frozen_string_literal: true

module AppstoreWebhooks
  class SubscriptionEvent < ApplicationRecord
    self.table_name = "subscription_events"

    belongs_to :subscription,
               class_name: "AppstoreWebhooks::Subscription"
    belongs_to :webhook_notification,
               class_name: "AppstoreWebhooks::Notification"

    validates :next_status, presence: true
    validates :effective_at, presence: true
  end
end
