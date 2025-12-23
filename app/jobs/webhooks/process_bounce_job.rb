module Webhooks
  class ProcessBounceJob < ApplicationJob
    queue_as :webhooks

    # Retry with exponential backoff
    retry_on StandardError, wait: :exponentially_longer, attempts: 5

    def perform(webhook_event_id)
      webhook_event = WebhookEvent.find(webhook_event_id)

      # Skip if already processed
      if webhook_event.processed?
        Rails.logger.info("[ProcessBounceJob] WebhookEvent #{webhook_event_id} already processed")
        return
      end

      # Parse the payload
      begin
        payload = JSON.parse(webhook_event.payload, symbolize_names: true)
      rescue JSON::ParserError => e
        Rails.logger.error("[ProcessBounceJob] Failed to parse payload: #{e.message}")
        webhook_event.mark_processed!
        return
      end

      # Extract bounce information
      bounce = payload[:bounce]
      mail = payload[:mail]

      unless bounce && mail
        Rails.logger.error("[ProcessBounceJob] Missing bounce or mail data in payload")
        webhook_event.mark_processed!
        return
      end

      # Determine bounce type (Hard or Soft)
      bounce_type = bounce[:bounceType]&.downcase # "Permanent" or "Transient"
      bounce_subtype = bounce[:bounceSubType]
      timestamp = bounce[:timestamp]

      # Map AWS bounce types to our schema
      mapped_bounce_type = case bounce_type
      when "permanent", "undetermined"
        "permanent"
      when "transient"
        "transient"
      else
        "permanent" # Default to permanent for safety
      end

      # Process each bounced recipient
      bounced_recipients = bounce[:bouncedRecipients] || []
      bounced_recipients.each do |recipient|
        email = recipient[:emailAddress]
        diagnostic_code = recipient[:diagnosticCode]
        action = recipient[:action]
        status = recipient[:status]

        # Build bounce reason
        bounce_reason = [
          bounce_subtype,
          diagnostic_code,
          status
        ].compact.join(" - ")

        # Find campaign_send by message ID
        message_id = mail[:messageId]
        campaign_send = CampaignSend.find_by(ses_message_id: message_id)

        if campaign_send
          # Mark campaign_send as bounced
          campaign_send.mark_bounced!(mapped_bounce_type, bounce_reason)

          Rails.logger.info("[ProcessBounceJob] CampaignSend #{campaign_send.id} marked as bounced (#{mapped_bounce_type})")
        else
          # Try to find subscriber by email and mark as bounced
          subscriber = Subscriber.find_by(email: email)

          if subscriber && mapped_bounce_type == "permanent"
            subscriber.mark_bounced!
            Rails.logger.info("[ProcessBounceJob] Subscriber #{subscriber.id} marked as bounced")
          else
            Rails.logger.warn("[ProcessBounceJob] Could not find campaign_send or subscriber for bounce: #{email}")
          end
        end
      end

      # Mark webhook event as processed
      webhook_event.mark_processed!

      Rails.logger.info("[ProcessBounceJob] Processed bounce for WebhookEvent #{webhook_event_id}")
    end
  end
end
