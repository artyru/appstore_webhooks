# frozen_string_literal: true

require "test_helper"
require "ostruct"

module AppstoreWebhooks
  class RemoteSubscriptionSyncServiceTest < ActiveSupport::TestCase
    class FakeVerifier
      attr_reader :calls

      def initialize(responses)
        @responses = responses.dup
        @calls = []
      end

      def verify_and_decode_signed_transaction(payload)
        @calls << payload
        @responses.shift
      end
    end

    def setup
      @original_transaction_id = "10000000000000"
      @subscription = create_subscription(original_transaction_id: @original_transaction_id)
    end

    def test_fetches_status_and_decodes_transactions
      decoded_transaction = OpenStruct.new(transaction_id: "tx-1")
      verifier = FakeVerifier.new([decoded_transaction])

      status_response = OpenStruct.new(data: [])
      history_response = OpenStruct.new(signed_transactions: ["signed-jws"])

      client = Minitest::Mock.new
      client.expect(:get_all_subscription_statuses, status_response, [@original_transaction_id])
      client.expect(:get_transaction_history, history_response, [@original_transaction_id])

      result = RemoteSubscriptionSyncService.new(
        subscription: @subscription,
        client: client,
        verifier: verifier
      ).call

      assert_equal status_response, result.status_response
      assert_equal [decoded_transaction], result.decoded_transactions
      assert_equal ["signed-jws"], verifier.calls
      client.verify
    end

    def test_handles_empty_history
      verifier = FakeVerifier.new([])
      status_response = OpenStruct.new(data: [])
      history_response = OpenStruct.new(signed_transactions: nil)

      client = Minitest::Mock.new
      client.expect(:get_all_subscription_statuses, status_response, [@original_transaction_id])
      client.expect(:get_transaction_history, history_response, [@original_transaction_id])

      result = RemoteSubscriptionSyncService.new(
        subscription: @subscription,
        client: client,
        verifier: verifier
      ).call

      assert_equal [], result.decoded_transactions
      client.verify
    end

    def test_requires_original_transaction_id
      assert_raises(ArgumentError) do
        RemoteSubscriptionSyncService.new(subscription: OpenStruct.new(original_transaction_id: nil))
      end
    end
  end
end
