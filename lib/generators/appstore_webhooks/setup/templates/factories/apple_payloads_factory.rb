# frozen_string_literal: true

FactoryBot.define do
  factory :apple_transaction_payload, class: Hash do
    bundleId { 'team.memriq.test' }
    productId { 'pro.weekly' }
    originalTransactionId { SecureRandom.uuid }
    transactionId { originalTransactionId }
    appAccountToken { SecureRandom.uuid }
    environment { 'LocalTesting' }
    signedDate { (Time.current.to_i * 1000) }
    purchaseDate { signedDate }
    expiresDate { (1.hour.from_now.to_i * 1000) }
    quantity { 1 }
    type { 'Auto-Renewable Subscription' }
    transactionReason { 'PURCHASE' }
    appTransactionId { SecureRandom.uuid }
    storefront { 'USA' }
    storefrontId { '143441' }
    currency { 'USD' }
    subscriptionGroupIdentifier { '99999999' }
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

  factory :apple_renewal_payload, class: Hash do
    originalTransactionId { SecureRandom.uuid }
    autoRenewStatus { 1 }
    environment { 'LocalTesting' }
    renewalDate { (1.day.from_now.to_i * 1000) }
    recentSubscriptionStartDate { (Time.current.to_i * 1000) }
    autoRenewProductId { 'pro.weekly' }
    productId { 'pro.weekly' }
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
end
