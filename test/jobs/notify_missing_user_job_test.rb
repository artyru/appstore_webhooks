# frozen_string_literal: true

require 'test_helper'

class NotifyMissingUserJobTest < ActiveSupport::TestCase
  def setup
    @notification = create_notification
  end

  def test_delivers_missing_user_email_when_notification_exists
    delivered_args = nil
    mailer = Minitest::Mock.new
    mailer.expect(:deliver_now, true)

    AppstoreWebhooks::NotificationMailer.stub(:missing_user, ->(notification, token) {
      delivered_args = [notification, token]
      mailer
    }) do
      AppstoreWebhooks::NotifyMissingUserJob.perform_now(@notification.id, 'token-123')
    end

    assert_equal [@notification, 'token-123'], delivered_args
    mailer.verify
  end

  def test_returns_silently_when_notification_missing
    AppstoreWebhooks::NotificationMailer.stub(:missing_user, ->(*) { flunk('should not deliver mailer') }) do
      AppstoreWebhooks::NotifyMissingUserJob.perform_now('missing-id', 'token-123')
    end

    assert_empty ActionMailer::Base.deliveries
  end
end
