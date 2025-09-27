# frozen_string_literal: true

require 'base64'

module AppleWebhookPayloadHelper
  def encode_apple_jws(payload)
    header = Base64.urlsafe_encode64({ alg: 'none', kid: nil, typ: 'JWT' }.to_json, padding: false)
    body   = Base64.urlsafe_encode64(payload.to_json, padding: false)
    [header, body, ''].join('.')
  end
end

RSpec.configure do |config|
  config.include AppleWebhookPayloadHelper
end
