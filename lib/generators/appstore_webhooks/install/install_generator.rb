# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record"
require "fileutils"

module AppstoreWebhooks
  module Generators
    class InstallGenerator < Rails::Generators::Base
      include Rails::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      class_option :skip_pundit,
                   type: :boolean,
                   default: false,
                   desc: "Skip generating the sample Pundit policy for entitlements."

      desc "Installs AppstoreWebhooks initializer, entitlements config, and migrations."

      def copy_initializer
        template "initializer.rb", "config/initializers/appstore_webhooks.rb"
      end

      def copy_entitlements_config
        target = "config/appstore_webhooks_entitlements.yml"
        if File.exist?(target)
          say_status :skip, "appstore_webhooks_entitlements.yml already exists", :yellow
        else
          template "appstore_webhooks_entitlements.yml", target
        end
      end

      def copy_pundit_policy
        return if options[:skip_pundit]

        target_dir = policies_root
        target_path = File.join(target_dir, "dictionary_word_policy.rb")

        if File.exist?(target_path)
          say_status :skip, "dictionary_word_policy.rb already exists", :yellow
        else
          template "policies/dictionary_word_policy.rb", target_path
        end
      end

      def copy_migrations
        migration_template "create_subscriptions.rb", File.join("db/migrate", "create_subscriptions.rb")
        migration_template "create_appstore_webhook_notifications.rb",
                           File.join("db/migrate", "create_appstore_webhook_notifications.rb")
        migration_template "create_subscription_events.rb", File.join("db/migrate", "create_subscription_events.rb")
      end

      def self.next_migration_number(_dirname)
        @migration_number ||= Time.now.utc.strftime("%Y%m%d%H%M%S").to_i
        @migration_number += 1
        @migration_number.to_s
      end

      private

      def policies_root
        root = "app/policies"
        FileUtils.mkdir_p(root) unless Dir.exist?(root)
        root
      end
    end
  end
end
