# frozen_string_literal: true

AppstoreWebhooks.configure do |config|
  # config.user_class = 'User'
  # config.user_token_column = :app_account_token
  config.alert_email = ENV['APPSTORE_ALERT_EMAIL']
end
