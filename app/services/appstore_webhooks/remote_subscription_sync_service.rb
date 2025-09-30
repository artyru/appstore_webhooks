# frozen_string_literal: true

module AppstoreWebhooks
  class RemoteSubscriptionSyncService
    STATUS_MAP = {
      'ACTIVE' => 'active',
      'EXPIRED' => 'expired',
      'BILLING_RETRY' => 'billing_retry',
      'BILLING_GRACE_PERIOD' => 'grace',
      'REVOKED' => 'revoked'
    }.freeze

    TRANSACTION_TIMESTAMP_FIELDS = %i[
      signed_date
      event_date
      purchase_date
      expires_date
      grace_period_expires_date
    ].freeze

    RENEWAL_TIMESTAMP_FIELDS = %i[
      signed_date
      event_date
      renewal_date
      expires_date
      grace_period_expires_date
    ].freeze

    Result = Struct.new(:status_response, :decoded_transactions, :latest_transaction, keyword_init: true)

    def initialize(subscription: nil, original_transaction_id: nil, client: nil, verifier: nil, time_source: nil)
      @subscription = subscription
      @original_transaction_id = original_transaction_id || subscription&.original_transaction_id
      raise ArgumentError, 'original_transaction_id is required' if @original_transaction_id.to_s.empty?

      @client = client || AppstoreSDK::Client::Base.new
      @verifier = verifier || build_verifier
      @time_source = time_source || Time
    end

    def call
      status = client.get_all_subscription_statuses(original_transaction_id)
      history = client.get_transaction_history(original_transaction_id)

      latest = decode_latest_status(status)

      if subscription
        if latest.nil?
          touch_last_synced
        elsif stale_payload?(latest)
          log_stale_remote_sync(latest)
          touch_last_synced
        else
          update_subscription(latest)
        end
      end

      Result.new(
        status_response: status,
        decoded_transactions: decode_transactions(history&.signed_transactions),
        latest_transaction: latest
      )
    end

    private

    attr_reader :subscription, :original_transaction_id, :client, :verifier, :time_source

    def build_verifier
      AppstoreSDK::Verification::SignedDataVerifier.new(
        AppstoreSDK.configuration.root_certificates,
        AppstoreSDK.configuration.enable_online_checks,
        AppstoreSDK.configuration.environment,
        AppstoreSDK.configuration.bundle_id,
        app_apple_id: AppstoreSDK.configuration.app_apple_id,
        chain_verifier: AppstoreSDK.configuration.chain_verifier
      )
    end

    def decode_latest_status(status_response)
      groups = Array(status_response&.data)
      groups.each do |group|
        transactions = Array(group&.last_transactions)
        next if transactions.empty?

        tx_item = transactions.first
        decoded_transaction = decode_signed_transaction(tx_item&.signed_transaction_info)
        decoded_renewal = decode_signed_renewal(tx_item&.signed_renewal_info)

        return {
          status: tx_item&.status,
          raw_status: tx_item&.raw_status,
          transaction: decoded_transaction,
          renewal: decoded_renewal
        }
      end
      nil
    end

    def decode_transactions(payloads)
      Array(payloads).filter_map do |payload|
        decode_signed_transaction(payload)
      end
    end

    def decode_signed_transaction(payload)
      return nil if payload.to_s.empty?

      verifier.verify_and_decode_signed_transaction(payload)
    rescue StandardError => error
      log_decode_failure('transaction', error)
      nil
    end

    def decode_signed_renewal(payload)
      return nil if payload.to_s.empty?

      verifier.verify_and_decode_signed_renewal_info(payload)
    rescue StandardError => error
      log_decode_failure('renewal', error)
      nil
    end

    def log_decode_failure(kind, error)
      return unless defined?(Rails) && Rails.logger

      Rails.logger.warn(
        "[appstore_webhooks] failed to decode signed #{kind} for #{original_transaction_id}: #{error.message}"
      )
    end

    def update_subscription(latest)
      tx = latest[:transaction]
      renewal = latest[:renewal]
      updates = {
        last_synced_at: current_time
      }

      if tx
        updates[:product_id] = tx.product_id if tx.respond_to?(:product_id)
        updates[:app_account_token] = tx.app_account_token if tx.respond_to?(:app_account_token) && tx.app_account_token.present?
        updates[:environment] = derive_environment(tx) if tx.respond_to?(:environment)
        updates[:expires_at] = parse_timestamp(tx, :expires_date)
        updates[:grace_period_expires_at] = parse_timestamp(tx, :grace_period_expires_date)
      end

      if renewal
        updates[:auto_renew_status] = interpret_auto_renew_status(renewal)
        updates[:grace_period_expires_at] ||= parse_timestamp(renewal, :grace_period_expires_date)
      end

      new_status = normalize_status(latest[:status], latest[:raw_status])
      updates[:status] = new_status if new_status && subscription.class.statuses.key?(new_status)

      subscription.update!(updates.compact)
    end

    def touch_last_synced
      subscription&.update!(last_synced_at: current_time)
    end

    def current_time
      if time_source.respond_to?(:current)
        time_source.current
      elsif defined?(Time.zone) && Time.zone
        Time.zone.now
      else
        Time.now
      end
    end

    def derive_environment(transaction)
      env = if transaction.respond_to?(:environment)
              transaction.environment
            elsif transaction.respond_to?(:raw_environment)
              transaction.raw_environment
            end
      env.to_s.underscore if env
    end

    def interpret_auto_renew_status(renewal)
      value = renewal&.auto_renew_status
      if value.respond_to?(:name)
        return value.name == 'ON'
      end
      raw = renewal&.raw_auto_renew_status
      return true if raw.to_s == '1'
      return false if raw.to_s == '0'

      nil
    end

    def normalize_status(status_obj, raw_status)
      if status_obj.respond_to?(:name)
        mapped = STATUS_MAP[status_obj.name]
        return mapped if mapped
      end

      STATUS_MAP.fetch(raw_status, nil)
    end

    def parse_timestamp(obj, attribute)
      return nil unless obj.respond_to?(attribute)

      raw = obj.public_send(attribute)
      return nil if raw.nil?

      if raw.is_a?(Integer)
        to_time(raw)
      elsif raw.is_a?(String) && raw.match?(/^\d+$/)
        to_time(raw.to_i)
      else
        Time.zone ? Time.zone.parse(raw.to_s) : Time.parse(raw.to_s)
      end
    rescue StandardError
      nil
    end

    def to_time(millis)
      if defined?(Time.zone) && Time.zone
        Time.zone.at(millis / 1000.0)
      else
        Time.at(millis / 1000.0)
      end
    end

    def stale_payload?(latest)
      return false unless subscription&.last_synced_at

      timestamp = latest_event_timestamp(latest)
      return false unless timestamp

      timestamp <= subscription.last_synced_at
    end

    def latest_event_timestamp(latest)
      timestamps = []

      if (transaction = latest[:transaction])
        TRANSACTION_TIMESTAMP_FIELDS.each do |field|
          value = parse_timestamp(transaction, field)
          timestamps << value if value
        end
      end

      if (renewal = latest[:renewal])
        RENEWAL_TIMESTAMP_FIELDS.each do |field|
          value = parse_timestamp(renewal, field)
          timestamps << value if value
        end
      end

      timestamps.compact.max
    end

    def log_stale_remote_sync(latest)
      return unless defined?(Rails) && Rails.logger

      timestamp = latest_event_timestamp(latest)
      Rails.logger.info(
        "[appstore_webhooks] skip remote sync for #{original_transaction_id} (stale payload timestamp=#{timestamp&.iso8601})"
      )
    end
  end
end
