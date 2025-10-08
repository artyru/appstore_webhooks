# frozen_string_literal: true

module AppstoreWebhooks
  class Engine < ::Rails::Engine
    isolate_namespace AppstoreWebhooks

    initializer "appstore_webhooks.configure_appstore_sdk", before: "appstore_webhooks.subscribe_webhooks" do
      config = AppstoreWebhooks.configuration

      AppstoreSDK.configure do |app_config|
        app_config.bundle_id = config.bundle_id if config.bundle_id
        app_config.environment = config.environment if config.environment
        app_config.issuer_id = config.issuer_id if config.issuer_id
        app_config.key_id = config.key_id if config.key_id
        app_config.private_key = config.private_key if config.private_key
        app_config.app_apple_id = config.app_apple_id if config.app_apple_id
        app_config.cache = config.cache if config.cache
        app_config.enable_online_checks = config.enable_online_checks unless config.enable_online_checks.nil?
        app_config.verification_enabled = config.verification_enabled unless config.verification_enabled.nil?
        app_config.chain_verifier = config.chain_verifier if config.chain_verifier
      end
    end

    rake_tasks do
      load File.expand_path("../tasks/appstore_webhooks.rake", __dir__)
    end

    initializer "appstore_webhooks.subscribe_webhooks" do
      AppstoreSDK.on_notification do |payload|
        AppstoreWebhooks::ProcessNotificationWorker.perform_now(payload.as_json)
      end
    end
  end
end
