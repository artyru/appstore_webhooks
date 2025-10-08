# frozen_string_literal: true

module AppstoreWebhooks
  class Notification < ApplicationRecord
    self.table_name = "appstore_webhook_notifications"

    STATES = {
      pending: "pending",
      processing: "processing",
      processed: "processed",
      failed: "failed"
    }.freeze

    belongs_to :subscription,
               class_name: "AppstoreWebhooks::Subscription",
               optional: true
    has_many :subscription_events,
             class_name: "AppstoreWebhooks::SubscriptionEvent",
             foreign_key: :webhook_notification_id,
             dependent: :nullify

    enum :processing_state, STATES

    validates :notification_uuid, presence: true, uniqueness: true
    validates :notification_type, presence: true
    validates :processing_state, inclusion: { in: STATES.values }

    scope :unprocessed, -> { where(processing_state: STATES[:pending]) }
  end
end
