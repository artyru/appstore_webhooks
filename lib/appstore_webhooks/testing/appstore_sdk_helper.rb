# frozen_string_literal: true

module AppstoreWebhooks
  module Testing
    # Helper for configuring AppstoreSDK in test mode
    #
    # Provides :appstore_sdk_test_mode metadata for automatic configuration
    # and HTTP stub setup for AppstoreSDK API endpoints.
    #
    # @example Auto-configuration via metadata
    #   describe 'Subscriptions', :appstore_sdk_test_mode do
    #     it 'syncs subscription' do
    #       # AppstoreSDK configured for local testing
    #       # HTTP stubs for /inApps/v1/* endpoints set up
    #     end
    #   end
    #
    # @example Manual configuration
    #   before do
    #     setup_appstore_sdk_test_mode
    #     stub_appstore_sdk_endpoints
    #   end
    #
    #   after do
    #     restore_appstore_sdk_configuration
    #   end
    module AppstoreSdkHelper
      # Store original configuration for restoration
      def save_appstore_sdk_configuration
        @_appstore_sdk_original_config = {
          environment: AppstoreSDK.configuration.environment,
          bundle_id: AppstoreSDK.configuration.bundle_id,
          verification_enabled: AppstoreSDK.configuration.verification_enabled,
          key_id: AppstoreSDK.configuration.key_id
        }
      end

      # Configure AppstoreSDK for local testing
      def setup_appstore_sdk_test_mode
        save_appstore_sdk_configuration

        AppstoreSDK.configuration.environment = :local_testing
        AppstoreSDK.configuration.bundle_id = "team.memriq.test"
        AppstoreSDK.configuration.verification_enabled = false
        AppstoreSDK.configuration.key_id = "test-key-id"
      end

      # Restore original AppstoreSDK configuration
      def restore_appstore_sdk_configuration
        return unless defined?(@_appstore_sdk_original_config) && @_appstore_sdk_original_config

        AppstoreSDK.configuration.environment = @_appstore_sdk_original_config[:environment]
        AppstoreSDK.configuration.bundle_id = @_appstore_sdk_original_config[:bundle_id]
        AppstoreSDK.configuration.verification_enabled = @_appstore_sdk_original_config[:verification_enabled]
        AppstoreSDK.configuration.key_id = @_appstore_sdk_original_config[:key_id]

        @_appstore_sdk_original_config = nil
      end

      # Setup HTTP stubs for AppstoreSDK endpoints (requires WebMock)
      #
      # @param subscription_response [Hash] Response for subscription endpoint
      # @param history_response [Hash] Response for history endpoint
      def stub_appstore_sdk_endpoints(subscription_response: { "data" => [] }, history_response: { "data" => [] })
        raise "WebMock required for AppstoreSDK stubs" unless defined?(WebMock)

        WebMock.stub_request(:get, %r{https://local-testing-base-url/inApps/v1/subscriptions/.*})
          .to_return(
            status: 200,
            body: subscription_response.to_json,
            headers: { "Content-Type" => "application/json" }
          )

        WebMock.stub_request(:get, %r{https://local-testing-base-url/inApps/v1/history/.*})
          .to_return(
            status: 200,
            body: history_response.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      # Setup stub for subscription lookup returning active subscription
      #
      # @param transaction_id [String] Original transaction ID
      # @param product_id [String] Product ID
      # @param app_account_token [String] App account token
      def stub_active_subscription(transaction_id:, product_id: "pro.weekly", app_account_token: nil)
        transaction_payload = FactoryBot.build(:apple_transaction_payload,
          originalTransactionId: transaction_id,
          productId: product_id,
          appAccountToken: app_account_token,
          expiresDate: (1.month.from_now.to_i * 1000)
        )

        signed_transaction = encode_apple_jws(transaction_payload)

        WebMock.stub_request(:get, %r{https://local-testing-base-url/inApps/v1/subscriptions/#{transaction_id}})
          .to_return(
            status: 200,
            body: {
              "data" => [{
                "lastTransactions" => [{
                  "signedTransactionInfo" => signed_transaction,
                  "status" => 1
                }]
              }]
            }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end
    end
  end
end
