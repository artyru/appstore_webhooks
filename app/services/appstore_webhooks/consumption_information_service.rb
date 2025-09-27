# frozen_string_literal: true

module AppstoreWebhooks
  class ConsumptionInformationService
    def initialize(transaction_payload:, subscription: nil, consented: true, consumption_status: nil)
      @transaction_payload = (transaction_payload || {}).with_indifferent_access
      @subscription = subscription
      @consented = consented
      @consumption_status = consumption_status
    end

    def call
      transaction_id = transaction_payload[:transaction_id]
      raise ArgumentError, 'transaction_id is required to send consumption information' if transaction_id.blank?

      client.send_consumption_data(transaction_id, build_consumption_request)
    end

    private

    attr_reader :transaction_payload, :subscription, :consented, :consumption_status

    def client
      @client ||= AppstoreSDK::Client::Base.new
    end

    def build_consumption_request
      builder_class = AppstoreWebhooks.configuration.consumption_builder_constant
      builder = builder_class.new(subscription: subscription, transaction_payload: transaction_payload)
      builder.call(consented: consented, consumption_status: consumption_status)
    end
  end
end
