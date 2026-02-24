# frozen_string_literal: true

require_relative "testing/apple_payload_helper"
require_relative "testing/factories"
require_relative "testing/appstore_sdk_helper"

module AppstoreWebhooks
  module Testing
    class << self
      # Configures RSpec with testing helpers and factories
      # Call this in rails_helper.rb or spec_helper.rb
      #
      # @example
      #   require 'appstore_webhooks/testing'
      #   AppstoreWebhooks::Testing.configure_rspec!
      #
      # Available metadata:
      #   :appstore_sdk_test_mode - auto configure AppstoreSDK for testing
      #
      def configure_rspec!
        return unless defined?(RSpec)

        RSpec.configure do |config|
          config.include ApplePayloadHelper, type: :request
          config.include AppstoreSdkHelper, type: :request

          # Around hook for :appstore_sdk_test_mode metadata
          # Auto-configures AppstoreSDK and stubs HTTP endpoints
          #
          # @example
          #   describe 'Subscriptions', :appstore_sdk_test_mode do
          #     it 'works' do
          #       # AppstoreSDK.configuration.environment = :local_testing
          #       # HTTP stubs for /inApps/v1/* set up
          #     end
          #   end
          config.around(:each, :appstore_sdk_test_mode) do |example|
            setup_appstore_sdk_test_mode
            stub_appstore_sdk_endpoints if defined?(WebMock)
            example.run
          ensure
            restore_appstore_sdk_configuration
          end
        end
      end
    end
  end
end
