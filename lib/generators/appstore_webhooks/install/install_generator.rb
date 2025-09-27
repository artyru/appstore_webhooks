# frozen_string_literal: true

require 'rails/generators'
require 'rails/generators/active_record'

module AppstoreWebhooks
  module Generators
    class InstallGenerator < Rails::Generators::Base
      include Rails::Generators::Migration

      source_root File.expand_path('templates', __dir__)

      desc 'Installs AppstoreWebhooks initializer and migrations.'

      def copy_initializer
        template 'initializer.rb', 'config/initializers/appstore_webhooks.rb'
      end

      def copy_migrations
        migration_template 'create_subscriptions.rb', File.join('db/migrate', 'create_subscriptions.rb')
        migration_template 'create_appstore_webhook_notifications.rb', File.join('db/migrate', 'create_appstore_webhook_notifications.rb')
        migration_template 'create_subscription_events.rb', File.join('db/migrate', 'create_subscription_events.rb')
      end

      def self.next_migration_number(dirname)
        @migration_number ||= Time.now.utc.strftime('%Y%m%d%H%M%S').to_i
        @migration_number += 1
        @migration_number.to_s
      end
    end
  end
end
