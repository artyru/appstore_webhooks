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
      # AppstoreSDK is automatically configured for local_testing mode
      # in all request specs. HTTP endpoints are stubbed to prevent real requests.
      #
      # Use :skip_appstore_sdk_test_mode to disable for specific tests.
      #
      def configure_rspec!
        return unless defined?(RSpec)

        RSpec.configure do |config|
          config.include ApplePayloadHelper, type: :request
          config.include AppstoreSdkHelper, type: :request

          # Auto-configure AppstoreSDK for all request specs
          # Prevents accidental real HTTP requests to Apple APIs
          config.around(:each, type: :request) do |example|
            next example.run if example.metadata[:skip_appstore_sdk_test_mode]

            setup_appstore_sdk_test_mode
            stub_appstore_sdk_endpoints if defined?(WebMock)
            example.run
          ensure
            restore_appstore_sdk_configuration unless example.metadata[:skip_appstore_sdk_test_mode]
          end
        end
      end
    end
  end
end
