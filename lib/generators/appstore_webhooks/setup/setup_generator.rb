# frozen_string_literal: true

require 'rails/generators'
require 'fileutils'

module AppstoreWebhooks
  module Generators
    class SetupGenerator < Rails::Generators::Base
      source_root File.expand_path('templates', __dir__)

      class_option :with_request_spec,
                   type: :boolean,
                   default: false,
                   desc: 'Generate an example RSpec request spec for the webhook endpoint.'

      desc 'Configures host application test factories and helpers for AppstoreWebhooks models.'

      def create_factories
        target_root = determine_factories_root
        target_dir = File.join(target_root, 'appstore_webhooks')

        empty_directory target_dir

        template 'factories/subscription_factory.rb', File.join(target_dir, 'subscription.rb')
        template 'factories/notification_factory.rb', File.join(target_dir, 'notification.rb')
        template 'factories/subscription_event_factory.rb', File.join(target_dir, 'subscription_event.rb')
        template 'factories/apple_payloads_factory.rb', File.join(target_dir, 'apple_payloads.rb')
      end

      def create_support_files
        target_root = determine_support_root
        FileUtils.mkdir_p(target_root)

        template 'support/apple_webhook_payload_helper.rb', File.join(target_root, 'appstore_webhooks_payload_helper.rb')
      end

      def create_request_spec
        return unless options[:with_request_spec]

        requests_root = determine_requests_root
        unless requests_root
          say_status :skip, 'request spec (RSpec directory not found)', :yellow
          return
        end

        template 'spec/appstore_webhooks_request_spec.rb', File.join(requests_root, 'appstore_webhooks_spec.rb')
      end

      private

      def determine_factories_root
        return 'spec/factories' if Dir.exist?('spec/factories')
        return 'test/factories' if Dir.exist?('test/factories')

        say_status :create, 'spec/factories', :green
        FileUtils.mkdir_p('spec/factories')
        'spec/factories'
      end

      def determine_support_root
        if Dir.exist?('spec')
          'spec/support'
        elsif Dir.exist?('test')
          'test/support'
        else
          say_status :create, 'spec/support', :green
          FileUtils.mkdir_p('spec/support')
          'spec/support'
        end
      end

      def determine_requests_root
        return unless Dir.exist?('spec')

        FileUtils.mkdir_p('spec/requests')
        'spec/requests'
      end
    end
  end
end
