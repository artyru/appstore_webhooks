# frozen_string_literal: true

require_relative "apple_payload_helper"

# Gem-provided factories for testing Apple App Store webhooks
#
# Usage:
#   # In rails_helper.rb or spec_helper.rb:
#   require 'appstore_webhooks/testing'
#
#   # In specs:
#   webhook = build(:signed_apple_webhook, app_account_token: user.app_account_token)
#   post '/api/v1/appstore_webhooks', params: webhook, as: :json

if defined?(FactoryBot)
  FactoryBot.define do
    # Apple Transaction Info payload (for signedTransactionInfo)
    factory :apple_transaction_payload, class: Hash do
      bundleId { "team.memriq.test" }
      productId { "pro.weekly" }
      originalTransactionId { SecureRandom.uuid }
      transactionId { originalTransactionId }
      appAccountToken { SecureRandom.uuid }
      environment { "LocalTesting" }
      signedDate { (Time.current.to_i * 1000) }
      purchaseDate { signedDate }
      expiresDate { (1.hour.from_now.to_i * 1000) }
      quantity { 1 }
      type { "Auto-Renewable Subscription" }
      transactionReason { "PURCHASE" }
      appTransactionId { SecureRandom.uuid }
      storefront { "USA" }
      storefrontId { "143441" }
      currency { "USD" }
      subscriptionGroupIdentifier { "99999999" }
      rawType { type }
      rawTransactionReason { transactionReason }
      rawEnvironment { environment }
      offerIdentifier { nil }
      offerType { nil }
      offerPeriod { nil }
      revocationReason { nil }

      initialize_with { attributes.stringify_keys }

      trait :grace do
        status { 4 }
        gracePeriodExpiresDate { (30.minutes.from_now.to_i * 1000) }
      end

      trait :expired do
        expiresDate { (5.minutes.ago.to_i * 1000) }
        status { 2 }
      end

      trait :revoked do
        status { 5 }
        revocationReason { 0 }
        revocationDate { (Time.current.to_i * 1000) }
      end

      trait :normalized do
        after(:build) do |payload|
          payload.replace(payload.transform_keys { |key| key.to_s.underscore })
        end
      end
    end

    # Apple Renewal Info payload (for signedRenewalInfo)
    factory :apple_renewal_payload, class: Hash do
      originalTransactionId { SecureRandom.uuid }
      autoRenewStatus { 1 }
      environment { "LocalTesting" }
      renewalDate { (1.day.from_now.to_i * 1000) }
      recentSubscriptionStartDate { (Time.current.to_i * 1000) }
      autoRenewProductId { "pro.weekly" }
      productId { "pro.weekly" }
      priceIncreaseStatus { nil }

      initialize_with { attributes.stringify_keys }

      trait :auto_renew_disabled do
        autoRenewStatus { 0 }
        expirationIntent { 1 }
      end

      trait :billing_retry do
        isInBillingRetryPeriod { true }
      end

      trait :normalized do
        after(:build) do |payload|
          payload.replace(payload.transform_keys { |key| key.to_s.underscore })
        end
      end
    end

    # Complete Apple App Store Server Notification v2
    #
    # Generates a fully structured webhook payload with signed JWS tokens.
    #
    # Usage:
    #   # Basic subscription event
    #   webhook = build(:signed_apple_webhook, app_account_token: user.app_account_token)
    #   post '/api/v1/appstore_webhooks', params: webhook, as: :json
    #
    #   # Specific event types via traits
    #   build(:signed_apple_webhook, :did_renew)
    #   build(:signed_apple_webhook, :expired)
    #   build(:signed_apple_webhook, :refund)
    #   build(:signed_apple_webhook, :grace_period)
    #   build(:signed_apple_webhook, :did_change_renewal_status)
    #
    #   # Custom attributes
    #   build(:signed_apple_webhook,
    #     notification_type: 'DID_RENEW',
    #     app_account_token: user.app_account_token,
    #     original_transaction_id: 'existing-txn-123',
    #     product_id: 'pro.monthly'
    #   )
    factory :signed_apple_webhook, class: Hash do
      transient do
        # Notification attributes
        notification_type { "SUBSCRIBED" }
        subtype { "INITIAL_BUY" }
        notification_uuid { SecureRandom.uuid }

        # Transaction attributes
        app_account_token { SecureRandom.uuid }
        original_transaction_id { SecureRandom.uuid }
        transaction_id { original_transaction_id }
        product_id { "pro.weekly" }
        bundle_id { "team.memriq" }
        environment { "LocalTesting" }

        # Dates (milliseconds)
        signed_date { (Time.current.to_f * 1000).to_i }
        purchase_date { signed_date }
        expires_date { (1.week.from_now.to_f * 1000).to_i }
        renewal_date { expires_date }

        # Override payloads if needed
        custom_transaction_payload { nil }
        custom_renewal_payload { nil }
      end

      initialize_with do
        extend AppstoreWebhooks::Testing::ApplePayloadHelper

        # Build transaction payload
        transaction_payload = custom_transaction_payload || FactoryBot.build(:apple_transaction_payload,
          bundleId: bundle_id,
          productId: product_id,
          environment: environment,
          appAccountToken: app_account_token,
          originalTransactionId: original_transaction_id,
          transactionId: transaction_id,
          signedDate: signed_date,
          purchaseDate: purchase_date,
          expiresDate: expires_date)

        # Build renewal payload
        renewal_payload = custom_renewal_payload || FactoryBot.build(:apple_renewal_payload,
          environment: environment,
          originalTransactionId: original_transaction_id,
          productId: product_id,
          autoRenewProductId: product_id,
          renewalDate: renewal_date,
          recentSubscriptionStartDate: purchase_date)

        # Build notification payload
        notification_payload = {
          "notificationType" => notification_type,
          "subtype" => subtype,
          "notificationUUID" => notification_uuid,
          "data" => {
            "environment" => environment,
            "bundleId" => bundle_id,
            "bundleVersion" => "1",
            "signedTransactionInfo" => encode_apple_jws(transaction_payload),
            "signedRenewalInfo" => encode_apple_jws(renewal_payload),
            "status" => 1
          },
          "version" => "2.0",
          "signedDate" => signed_date
        }

        # Return final webhook body
        { signedPayload: encode_apple_jws(notification_payload) }
      end

      # === Event Type Traits ===

      trait :did_renew do
        notification_type { "DID_RENEW" }
        subtype { nil }
      end

      trait :did_change_renewal_status do
        notification_type { "DID_CHANGE_RENEWAL_STATUS" }
        subtype { "AUTO_RENEW_DISABLED" }
      end

      trait :expired do
        notification_type { "EXPIRED" }
        subtype { "VOLUNTARY" }
        expires_date { (5.minutes.ago.to_f * 1000).to_i }
      end

      trait :refund do
        notification_type { "REFUND" }
        subtype { nil }
      end

      trait :grace_period do
        notification_type { "DID_FAIL_TO_RENEW" }
        subtype { "GRACE_PERIOD" }
      end

      trait :billing_recovery do
        notification_type { "DID_RENEW" }
        subtype { "BILLING_RECOVERY" }
      end

      trait :revoke do
        notification_type { "REVOKE" }
        subtype { nil }
      end

      trait :consumption_request do
        notification_type { "CONSUMPTION_REQUEST" }
        subtype { nil }
      end
    end
  end
end
