# frozen_string_literal: true

module AppstoreWebhooks
  class RespondToConsumptionRequestJob < ApplicationJob
    queue_as :default

    def perform(notification_id)
      notification = Notification.find_by(id: notification_id)
      return unless notification

      notification.update!(processing_state: Notification::STATES[:processing])

      payload = (notification.transaction_payload || {}).with_indifferent_access
      original_transaction_id = payload[:original_transaction_id]
      subscription = Subscription.find_by(original_transaction_id: original_transaction_id)

      AppstoreWebhooks::ConsumptionInformationService.new(
        transaction_payload: payload,
        subscription: subscription
      ).call

      notification.update!(processing_state: Notification::STATES[:processed],
                           processing_error: nil)
    rescue StandardError => e
      notification&.update(processing_state: Notification::STATES[:failed],
                           processing_error: e.message)
      Rails.logger.error("Failed to send consumption info for notification #{notification_id}: #{e.message}")
      raise
    end
  end
end
