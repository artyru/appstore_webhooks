# frozen_string_literal: true

require 'base64'
require 'json'

module AppstoreWebhooks
  module Testing
    module ApplePayloadHelper
      module_function

      def encode_apple_jws(payload)
        header = Base64.urlsafe_encode64({ alg: 'none', kid: nil, typ: 'JWT' }.to_json, padding: false)
        body = Base64.urlsafe_encode64(payload.to_json, padding: false)
        [header, body, ''].join('.')
      end
    end
  end
end
