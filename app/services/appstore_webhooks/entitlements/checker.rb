# frozen_string_literal: true

require 'active_support/core_ext/hash/indifferent_access'
require 'active_support/core_ext/hash/keys'

module AppstoreWebhooks
  module Entitlements
    class Checker
      DEFAULT_ALLOWED_STATUSES = %w[active grace billing_retry canceled].freeze

      def self.call(user:, feature:, config: AppstoreWebhooks.configuration.entitlements)
        new(user: user, feature: feature, config: config).call
      end

      def initialize(user:, feature:, config:)
        @user = user
        @feature = feature.to_s
        @config = normalize_config(config)
      end

      def call
        return false unless user

        product_ids = required_product_ids
        return false if product_ids.empty?

        matching_subscriptions(product_ids).any? do |subscription|
          entitled_subscription?(subscription)
        end
      end

      private

      attr_reader :user, :feature, :config

      def normalize_config(value)
        return {} if value.nil?

        hash = value.respond_to?(:to_h) ? value.to_h : value
        return {} unless hash.is_a?(Hash)

        hash = if hash.respond_to?(:deep_stringify_keys)
                 hash.deep_stringify_keys
               else
                 hash.each_with_object({}) { |(key, val), memo| memo[key.to_s] = val }
               end

        hash = hash.with_indifferent_access if hash.respond_to?(:with_indifferent_access)
        hash
      end

      def feature_settings
        features = extract_hash(config[:features] || config['features'])
        extract_hash(features[feature] || features[feature.to_sym])
      end

      def required_product_ids
        Array(feature_settings[:product_ids]).map(&:to_s).reject(&:blank?)
      end

      def allowed_statuses
        Array(feature_settings[:allowed_statuses]).map(&:to_s).reject(&:blank?).presence || DEFAULT_ALLOWED_STATUSES
      end

      def extract_hash(value)
        return {} unless value.is_a?(Hash)

        if value.respond_to?(:with_indifferent_access)
          value.with_indifferent_access
        elsif value.respond_to?(:deep_stringify_keys)
          value.deep_stringify_keys.with_indifferent_access
        else
          value.each_with_object({}) { |(key, val), memo| memo[key.to_s] = val }.with_indifferent_access
        end
      end

      def matching_subscriptions(product_ids)
        scope =
          if user.respond_to?(:subscriptions)
            user.subscriptions
          elsif user
            AppstoreWebhooks::Subscription.where(user: user)
          end

        return AppstoreWebhooks::Subscription.none unless scope.respond_to?(:where)

        scope.where(product_id: product_ids)
      end

      def entitled_subscription?(subscription)
        status_allows?(subscription) && subscription.entitlement_active?(at: current_time)
      end

      def status_allows?(subscription)
        allowed_statuses.include?(subscription.status.to_s)
      end

      def current_time
        Time.zone ? Time.zone.now : Time.now
      end
    end
  end
end
