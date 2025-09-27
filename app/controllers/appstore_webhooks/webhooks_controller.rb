# frozen_string_literal: true

module AppstoreWebhooks
  class WebhooksController < ActionController::API
    rescue_from AppstoreSDK::Rails::NotificationProcessor::MissingSignedPayloadError, with: :render_bad_request
    rescue_from AppstoreSDK::Rails::NotificationProcessor::InvalidSignedPayloadError, with: :render_bad_request

    if defined?(::ActionDispatch::Http::Parameters::ParseError)
      rescue_from ::ActionDispatch::Http::Parameters::ParseError, with: :render_invalid_json
    end

    rescue_from AppstoreSDK::Verification::VerificationError, with: :render_verification_failure

    def create
      payload = processor.call(extract_signed_payload)
      AppstoreSDK::Notifications.broadcast(payload)
      head :ok
    end

    private

    def extract_signed_payload
      params[:signedPayload] || params[:signed_payload]
    end

    def processor
      configured_processor || default_processor
    end

    def configured_processor
      options = rails_appstore_options
      return unless options

      if options.respond_to?(:key?) && options.key?(:processor)
        options[:processor]
      elsif options.respond_to?(:processor)
        options.processor
      end
    end

    def rails_appstore_options
      configuration = rails_configuration
      return unless configuration.respond_to?(:appstore_sdk)

      configuration.appstore_sdk
    end

    def rails_configuration
      return unless defined?(::Rails)
      return unless ::Rails.respond_to?(:application)

      ::Rails.application&.config
    end

    def default_processor
      @default_processor ||= AppstoreSDK::Rails::NotificationProcessor.new
    end

    def render_bad_request(error)
      render json: { error: error_code(error) }, status: :bad_request
    end

    def render_invalid_json(_error)
      render json: { error: 'invalid_json' }, status: :bad_request
    end

    def render_verification_failure(error)
      render json: { error: error.status.name }, status: :unauthorized
    end

    def error_code(error)
      case error
      when AppstoreSDK::Rails::NotificationProcessor::MissingSignedPayloadError
        'missing_signed_payload'
      when AppstoreSDK::Rails::NotificationProcessor::InvalidSignedPayloadError
        'invalid_signed_payload'
      else
        'invalid_request'
      end
    end
  end
end
