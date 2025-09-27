# frozen_string_literal: true

module AppstoreWebhooks
  class NotifyMissingUserJob < ApplicationJob
    queue_as :default

    def perform(notification_id, app_account_token)
      notification = Notification.find_by(id: notification_id)
      return unless notification

      mailer = AppstoreWebhooks::NotificationMailer
      return unless mailer.available?

      mailer.missing_user(notification, app_account_token).deliver_now
    end
  end
end
