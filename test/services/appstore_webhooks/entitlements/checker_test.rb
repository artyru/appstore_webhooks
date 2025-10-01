# frozen_string_literal: true

require 'test_helper'

module AppstoreWebhooks
  module Entitlements
    class CheckerTest < ActiveSupport::TestCase
      def setup
        @user = create_user
        @feature = :dictionary_words
        AppstoreWebhooks.configuration.entitlements = {
          'features' => {
            'dictionary_words' => {
              'product_ids' => ['pro.weekly', 'pro.monthly']
            }
          }
        }
      end

      def test_returns_true_when_subscription_active
        create_subscription(user: @user, product_id: 'pro.weekly', status: 'active', expires_at: 1.day.from_now)

        assert Checker.call(user: @user, feature: @feature)
      end

      def test_returns_true_when_subscription_canceled_but_not_expired
        create_subscription(user: @user, product_id: 'pro.weekly', status: 'canceled', expires_at: 1.hour.from_now)

        assert Checker.call(user: @user, feature: @feature)
      end

      def test_returns_true_for_grace_period
        create_subscription(
          user: @user,
          product_id: 'pro.monthly',
          status: 'grace',
          expires_at: 1.day.ago,
          grace_period_expires_at: 1.day.from_now
        )

        assert Checker.call(user: @user, feature: @feature)
      end

      def test_returns_false_for_expired_subscription
        create_subscription(user: @user, product_id: 'pro.weekly', status: 'active', expires_at: 1.day.ago)

        refute Checker.call(user: @user, feature: @feature)
      end

      def test_returns_false_when_canceled_subscription_expired
        create_subscription(
          user: @user,
          product_id: 'pro.weekly',
          status: 'canceled',
          expires_at: 1.hour.ago,
          grace_period_expires_at: 1.day.from_now
        )

        refute Checker.call(user: @user, feature: @feature)
      end

      def test_returns_false_for_disallowed_status
        AppstoreWebhooks.configuration.entitlements = {
          'features' => {
            'dictionary_words' => {
              'product_ids' => ['pro.weekly'],
              'allowed_statuses' => ['active']
            }
          }
        }

        create_subscription(user: @user, product_id: 'pro.weekly', status: 'grace', expires_at: 1.day.from_now)

        refute Checker.call(user: @user, feature: @feature)
      end

      def test_returns_false_when_products_do_not_match
        create_subscription(user: @user, product_id: 'another.product', status: 'active', expires_at: 1.day.from_now)

        refute Checker.call(user: @user, feature: @feature)
      end

      def test_returns_false_when_feature_not_configured
        refute Checker.call(user: @user, feature: :unknown_feature)
      end

      def test_returns_false_when_user_missing
        refute Checker.call(user: nil, feature: @feature)
      end

      def test_handles_symbol_keys_configuration
        AppstoreWebhooks.configuration.entitlements = {
          features: {
            dictionary_words: {
              product_ids: ['pro.weekly']
            }
          }
        }

        create_subscription(user: @user, product_id: 'pro.weekly', status: 'active', expires_at: 1.day.from_now)

        assert Checker.call(user: @user, feature: @feature)
      end

    end
  end
end
