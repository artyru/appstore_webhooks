# frozen_string_literal: true

require "appstore_webhooks/testing/apple_payload_helper"

if defined?(RSpec)
  RSpec.configure do |config|
    config.include AppstoreWebhooks::Testing::ApplePayloadHelper, type: :request
  end
end

ActiveSupport::TestCase.include AppstoreWebhooks::Testing::ApplePayloadHelper if defined?(ActiveSupport::TestCase)
