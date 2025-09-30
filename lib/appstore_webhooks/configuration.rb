# frozen_string_literal: true

module AppstoreWebhooks
  class Configuration
    attr_accessor :user_class,
                  :user_token_column,
                  :alert_email,
                  :consumption_builder,
                  :bundle_id,
                  :environment,
                  :issuer_id,
                  :key_id,
                  :private_key,
                  :app_apple_id,
                  :cache,
                  :enable_online_checks,
                  :verification_enabled,
                  :chain_verifier

    attr_reader :entitlements

    def initialize
      @user_class = 'User'
      @user_token_column = :app_account_token
      @alert_email = nil
      @consumption_builder = 'AppstoreWebhooks::ConsumptionRequestBuilder'
      @bundle_id = nil
      @environment = default_environment
      @issuer_id = nil
      @key_id = nil
      @private_key = nil
      @app_apple_id = nil
      @cache = Rails.cache
      @enable_online_checks = false
      @verification_enabled = true
      @chain_verifier = nil
      @entitlements = {}
    end

    def entitlements=(value)
      @entitlements = normalize_entitlements(value)
    end

    def feature_entitlements(feature)
      entitlements.fetch('features', {}).fetch(feature.to_s, {})
    end

    def user_class_constant
      user_class.constantize
    end

    def consumption_builder_constant
      consumption_builder.is_a?(String) ? consumption_builder.constantize : consumption_builder
    end

    private

    def normalize_entitlements(value)
      return {} if value.nil?

      if value.respond_to?(:deep_stringify_keys)
        value.deep_stringify_keys
      elsif value.is_a?(Hash)
        value.transform_keys(&:to_s)
      else
        {}
      end
    end

    def default_environment
      Rails.env.production? ? :production : :sandbox
    end
  end
end
