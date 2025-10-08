# frozen_string_literal: true

AppstoreWebhooks.configure do |config|
  # config.user_class = 'User'
  # config.user_token_column = :app_account_token
  config.alert_email = ENV["APPSTORE_ALERT_EMAIL"]

  entitlements_path = Rails.root.join("config", "appstore_webhooks_entitlements.yml")
  config.entitlements = if entitlements_path.exist?
                          Rails.application.config_for(:appstore_webhooks_entitlements)
                        else
                          { "features" => {} }
                        end
end
