module Webhooks
  class ProcessDeliveryJob < ApplicationJob
    queue_as :webhooks

    # Retry with exponential backoff
    retry_on StandardError, wait: :exponentially_longer, attempts: 5

    def perform(webhook_event_id)
      webhook_event = WebhookEvent.find(webhook_event_id)

      # Skip if already processed
      if webhook_event.processed?
        Rails.logger.info("[ProcessDeliveryJob] WebhookEvent #{webhook_event_id} already processed")
        return
      end

      # Parse the payload
      begin
        payload = JSON.parse(webhook_event.payload, symbolize_names: true)
      rescue JSON::ParserError => e
        Rails.logger.error("[ProcessDeliveryJob] Failed to parse payload: #{e.message}")
        webhook_event.mark_processed!
        return
      end

      # Extract delivery information
      delivery = payload[:delivery]
      mail = payload[:mail]

      unless delivery && mail
        Rails.logger.error("[ProcessDeliveryJob] Missing delivery or mail data in payload")
        webhook_event.mark_processed!
        return
      end

      # Extract delivery details
      timestamp = delivery[:timestamp]
      processing_time_millis = delivery[:processingTimeMillis]
      recipients = delivery[:recipients] || mail[:destination] || []
      smtp_response = delivery[:smtpResponse]

      # Find campaign_send by message ID
      message_id = mail[:messageId]
      campaign_send = CampaignSend.find_by(ses_message_id: message_id)

      if campaign_send
        # Mark campaign_send as delivered
        campaign_send.mark_delivered!

        Rails.logger.info("[ProcessDeliveryJob] CampaignSend #{campaign_send.id} marked as delivered")
      else
        Rails.logger.warn("[ProcessDeliveryJob] Could not find campaign_send for delivery: #{message_id}")
      end

      # Mark webhook event as processed
      webhook_event.mark_processed!

      Rails.logger.info("[ProcessDeliveryJob] Processed delivery for WebhookEvent #{webhook_event_id}")
    end
  end
end
