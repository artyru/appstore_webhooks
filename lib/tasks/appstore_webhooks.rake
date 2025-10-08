# frozen_string_literal: true

def appstore_webhooks_truthy?(value, default: false)
  return default if value.nil?

  %w[1 true yes on].include?(value.to_s.strip.downcase)
end

namespace :appstore_webhooks do
  namespace :notifications do
    desc "Requeue failed App Store notifications for processing"
    task retry_failed: :environment do
      scope = AppstoreWebhooks::Notification.where(
        processing_state: AppstoreWebhooks::Notification::STATES[:failed]
      )

      limit = ENV.fetch("LIMIT", nil)&.to_i
      scope = scope.limit(limit) if limit&.positive?

      notifications = scope.order(:updated_at).to_a
      processed = 0

      notifications.each do |notification|
        if notification.raw_payload.blank?
          Rails.logger.warn(
            "[appstore_webhooks] skip notification ##{notification.id} (missing raw_payload)"
          )
          next
        end

        notification.with_lock do
          notification.update!(
            processing_state: AppstoreWebhooks::Notification::STATES[:pending],
            processing_error: nil
          )
        end

        AppstoreWebhooks::ProcessNotificationWorker.perform_later(notification.raw_payload)
        processed += 1
      end

      puts "Enqueued #{processed} notification(s)" unless ENV["SILENT"] == "true"
    end
  end

  namespace :subscriptions do
    desc "Sync a subscription with App Store Server API by original transaction id"
    task :sync, [:original_transaction_id] => :environment do |_, args|
      original_id = args[:original_transaction_id].presence || ENV["ORIGINAL_TRANSACTION_ID"]
      raise ArgumentError, "original_transaction_id is required" if original_id.to_s.empty?

      subscription = AppstoreWebhooks::Subscription.find_by(original_transaction_id: original_id)
      job_args = { original_transaction_id: original_id }
      job_args[:subscription_id] = subscription.id if subscription

      perform_async = appstore_webhooks_truthy?(ENV["ASYNC"], default: false)
      job_method = perform_async ? :perform_later : :perform_now

      AppstoreWebhooks::SyncSubscriptionJob.public_send(job_method, **job_args)

      unless ENV["SILENT"] == "true"
        verb = perform_async ? "Enqueued" : "Synced"
        puts "#{verb} subscription #{original_id}"
      end
    end

    desc "Sync subscriptions that have not been refreshed recently"
    task :sync_stale, [:stale_after_minutes] => :environment do |_, args|
      minutes = (args[:stale_after_minutes] || ENV["STALE_AFTER_MINUTES"] || "1440").to_i
      cutoff = if minutes.positive?
                 (Time.zone ? Time.zone.now : Time.now) - minutes.minutes
               end

      relation = AppstoreWebhooks::Subscription.order(:last_synced_at)
      relation = relation.where("last_synced_at IS NULL OR last_synced_at < ?", cutoff) if cutoff

      limit = ENV["LIMIT"].to_i
      batch_size = ENV["BATCH_SIZE"].to_i
      batch_size = 100 if batch_size <= 0

      perform_async = appstore_webhooks_truthy?(ENV["ASYNC"], default: true)
      job_method = perform_async ? :perform_later : :perform_now

      processed = 0

      if limit.positive?
        relation.limit(limit).each do |subscription|
          job_args = {
            subscription_id: subscription.id,
            original_transaction_id: subscription.original_transaction_id
          }
          AppstoreWebhooks::SyncSubscriptionJob.public_send(job_method, **job_args)
          processed += 1
        end
      else
        relation.find_each(batch_size: batch_size) do |subscription|
          job_args = {
            subscription_id: subscription.id,
            original_transaction_id: subscription.original_transaction_id
          }
          AppstoreWebhooks::SyncSubscriptionJob.public_send(job_method, **job_args)
          processed += 1
        end
      end

      unless ENV["SILENT"] == "true"
        action = perform_async ? "Enqueued" : "Synced"
        puts "#{action} #{processed} subscription(s)"
      end
    end
  end
end
