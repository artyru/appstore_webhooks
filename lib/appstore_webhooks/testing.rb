# frozen_string_literal: true

require_relative "testing/apple_payload_helper"
require_relative "testing/factories"

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
      def configure_rspec!
        return unless defined?(RSpec)

        RSpec.configure do |config|
          config.include ApplePayloadHelper, type: :request
        end
      end
    end
  end
end
