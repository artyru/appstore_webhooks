# frozen_string_literal: true

require 'rails/generators'
require 'fileutils'

module AppstoreWebhooks
  module Generators
    class SetupGenerator < Rails::Generators::Base
      source_root File.expand_path('templates', __dir__)

      desc 'Configures host application test factories for AppstoreWebhooks models.'

      def create_factories
        target_root = determine_factories_root
        target_dir = File.join(target_root, 'appstore_webhooks')

        empty_directory target_dir

        template 'factories/subscription_factory.rb', File.join(target_dir, 'subscription.rb')
        template 'factories/notification_factory.rb', File.join(target_dir, 'notification.rb')
        template 'factories/subscription_event_factory.rb', File.join(target_dir, 'subscription_event.rb')
      end

      private

      def determine_factories_root
        return 'spec/factories' if Dir.exist?('spec/factories')
        return 'test/factories' if Dir.exist?('test/factories')

        say_status :create, 'spec/factories', :green
        FileUtils.mkdir_p('spec/factories')
        'spec/factories'
      end
    end
  end
end
