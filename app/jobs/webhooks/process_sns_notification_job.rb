module Webhooks
  class ProcessSnsNotificationJob < ApplicationJob
    queue_as :webhooks

    # Retry with exponential backoff
    retry_on StandardError, wait: :exponentially_longer, attempts: 5

    def perform(webhook_event_id)
      webhook_event = WebhookEvent.find(webhook_event_id)

      # Skip if already processed
      if webhook_event.processed?
        Rails.logger.info("[ProcessSnsNotificationJob] WebhookEvent #{webhook_event_id} already processed")
        return
      end

      # Parse the SES message payload
      begin
        payload = JSON.parse(webhook_event.payload, symbolize_names: true)
      rescue JSON::ParserError => e
        Rails.logger.error("[ProcessSnsNotificationJob] Failed to parse payload: #{e.message}")
        webhook_event.mark_processed! # Mark as processed to avoid retry
        return
      end

      # Route to appropriate processing job based on event type
      case webhook_event.event_type
      when "bounce"
        Webhooks::ProcessBounceJob.perform_later(webhook_event_id)
      when "complaint"
        Webhooks::ProcessComplaintJob.perform_later(webhook_event_id)
      when "delivery"
        Webhooks::ProcessDeliveryJob.perform_later(webhook_event_id)
      when "send"
        # Send events are informational, just mark as processed
        webhook_event.mark_processed!
        Rails.logger.info("[ProcessSnsNotificationJob] Send event processed for WebhookEvent #{webhook_event_id}")
      when "reject"
        # Reject events indicate message was rejected before sending
        handle_reject_event(webhook_event, payload)
      when "open", "click"
        # Open and click events from Configuration Sets (if enabled)
        # These are typically handled via tracking pixels/links instead
        webhook_event.mark_processed!
        Rails.logger.info("[ProcessSnsNotificationJob] #{webhook_event.event_type.capitalize} event received for WebhookEvent #{webhook_event_id}")
      else
        Rails.logger.warn("[ProcessSnsNotificationJob] Unknown event type: #{webhook_event.event_type}")
        webhook_event.mark_processed!
      end
    end

    private

    def handle_reject_event(webhook_event, payload)
      # Find the campaign_send by message ID
      message_id = payload.dig(:mail, :messageId)
      return unless message_id

      campaign_send = CampaignSend.find_by(ses_message_id: message_id)
      return unless campaign_send

      # Mark as failed
      reject_reason = payload.dig(:reject, :reason) || "Message rejected by SES"
      campaign_send.update!(
        status: "failed",
        bounce_reason: reject_reason
      )

      Rails.logger.info("[ProcessSnsNotificationJob] Message rejected for CampaignSend #{campaign_send.id}: #{reject_reason}")

      webhook_event.mark_processed!
    end
  end
end
