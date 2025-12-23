module Webhooks
  class ProcessComplaintJob < ApplicationJob
    queue_as :webhooks

    # Retry with exponential backoff
    retry_on StandardError, wait: :exponentially_longer, attempts: 5

    def perform(webhook_event_id)
      webhook_event = WebhookEvent.find(webhook_event_id)

      # Skip if already processed
      if webhook_event.processed?
        Rails.logger.info("[ProcessComplaintJob] WebhookEvent #{webhook_event_id} already processed")
        return
      end

      # Parse the payload
      begin
        payload = JSON.parse(webhook_event.payload, symbolize_names: true)
      rescue JSON::ParserError => e
        Rails.logger.error("[ProcessComplaintJob] Failed to parse payload: #{e.message}")
        webhook_event.mark_processed!
        return
      end

      # Extract complaint information
      complaint = payload[:complaint]
      mail = payload[:mail]

      unless complaint && mail
        Rails.logger.error("[ProcessComplaintJob] Missing complaint or mail data in payload")
        webhook_event.mark_processed!
        return
      end

      # Extract complaint details
      complaint_feedback_type = complaint[:complaintFeedbackType]
      timestamp = complaint[:timestamp]
      user_agent = complaint[:userAgent]
      complaint_subtype = complaint[:complaintSubType]

      # Process each complained recipient
      complained_recipients = complaint[:complainedRecipients] || []
      complained_recipients.each do |recipient|
        email = recipient[:emailAddress]

        # Find campaign_send by message ID
        message_id = mail[:messageId]
        campaign_send = CampaignSend.find_by(ses_message_id: message_id)

        if campaign_send
          # Mark campaign_send as complained
          campaign_send.mark_complained!

          Rails.logger.info("[ProcessComplaintJob] CampaignSend #{campaign_send.id} marked as complained")
        else
          # Try to find subscriber by email and mark as complained
          subscriber = Subscriber.find_by(email: email)

          if subscriber
            subscriber.mark_complained!
            Rails.logger.info("[ProcessComplaintJob] Subscriber #{subscriber.id} marked as complained")
          else
            Rails.logger.warn("[ProcessComplaintJob] Could not find campaign_send or subscriber for complaint: #{email}")
          end
        end
      end

      # Mark webhook event as processed
      webhook_event.mark_processed!

      Rails.logger.info("[ProcessComplaintJob] Processed complaint for WebhookEvent #{webhook_event_id}")
    end
  end
end
