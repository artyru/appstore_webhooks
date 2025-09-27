# frozen_string_literal: true

module AppstoreWebhooks
  class NotificationMailer < ApplicationMailer
    default(
      to: -> { alert_recipients },
      subject: 'App Store webhook requires attention'
    )

    def self.available?
      alert_recipients.any?
    end

    def self.alert_recipients
      Array(AppstoreWebhooks.configuration.alert_email)
        .flat_map { |value| value.to_s.split(/[;,\s]+/) }
        .reject(&:blank?)
    end

    def missing_user(notification, app_account_token)
      @notification = notification
      @app_account_token = app_account_token
      mail
    end
  end
end
