# frozen_string_literal: true

require 'test_helper'

class AppstoreWebhooks::WebhooksControllerTest < ActiveSupport::TestCase
  def teardown
    AppstoreWebhooks::WebhooksController.test_processor = nil
    super
  end

  def test_processes_signed_payload_and_broadcasts
    decoded_payload = Object.new
    processor = Minitest::Mock.new
    processor.expect(:call, decoded_payload, ['signed-token'])

    broadcast = Minitest::Mock.new
    broadcast.expect(:call, nil, [decoded_payload])

    AppstoreWebhooks::WebhooksController.test_processor = processor

    AppstoreSDK::Notifications.stub(:broadcast, ->(payload) { broadcast.call(payload) }) do
      status, _headers, body = invoke_controller(params: { 'signedPayload' => 'signed-token' })

      assert_equal 200, status
      assert_equal '', body
    end

    processor.verify
    broadcast.verify
  end

  def test_accepts_snake_case_signed_payload
    decoded_payload = Object.new
    processor = Minitest::Mock.new
    processor.expect(:call, decoded_payload, ['snake-token'])

    AppstoreWebhooks::WebhooksController.test_processor = processor

    AppstoreSDK::Notifications.stub(:broadcast, proc { |_payload| nil }) do
      status, _headers, _body = invoke_controller(params: { 'signed_payload' => 'snake-token' })
      assert_equal 200, status
    end

    processor.verify
  end

  def test_renders_bad_request_when_payload_missing
    error = AppstoreSDK::Rails::NotificationProcessor::MissingSignedPayloadError.new('signedPayload is required')

    AppstoreWebhooks::WebhooksController.test_processor = ->(*) { raise error }

    AppstoreSDK::Notifications.stub(:broadcast, proc { |_payload| flunk('should not broadcast') }) do
      status, _headers, body = invoke_controller(params: {})

      assert_equal 400, status
      assert_equal({ 'error' => 'missing_signed_payload' }, JSON.parse(body))
    end
  end

  def test_renders_unauthorized_when_broadcast_raises_verification_error
    decoded_payload = Object.new
    processor = Minitest::Mock.new
    processor.expect(:call, decoded_payload, ['signed-token'])

    status_code = AppstoreSDK::Verification::VerificationStatus::INVALID_ENVIRONMENT
    verification_error = AppstoreSDK::Verification::VerificationError.new(status_code)

    AppstoreWebhooks::WebhooksController.test_processor = processor

    AppstoreSDK::Notifications.stub(:broadcast, ->(_payload) { raise verification_error }) do
      status, _headers, body = invoke_controller(params: { 'signedPayload' => 'signed-token' })

      assert_equal 401, status
      assert_equal({ 'error' => 'INVALID_ENVIRONMENT' }, JSON.parse(body))
    end

    processor.verify
  end

  private

  def invoke_controller(params: {})
    env = Rack::MockRequest.env_for('/appstore_webhooks', method: 'POST', params: params)
    status, headers, body = AppstoreWebhooks::WebhooksController.action(:create).call(env)

    response_body = +''
    body.each { |chunk| response_body << chunk }
    body.close if body.respond_to?(:close)

    [status, headers, response_body]
  end
end
