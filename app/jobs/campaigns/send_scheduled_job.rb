module Campaigns
  class SendScheduledJob < ApplicationJob
    queue_as :default

    # Retry with exponential backoff if job fails
    retry_on StandardError, wait: :exponentially_longer, attempts: 3

    def perform(campaign_id)
      campaign = Campaign.find(campaign_id)

      # Only start if campaign is still scheduled
      unless campaign.scheduled?
        Rails.logger.info("[SendScheduledJob] Campaign #{campaign_id} is not scheduled (status: #{campaign.status})")
        return
      end

      # Check if scheduled time has arrived
      if campaign.scheduled_at > Time.current
        Rails.logger.info("[SendScheduledJob] Campaign #{campaign_id} scheduled time not yet reached")
        # Re-enqueue for the correct time
        self.class.set(wait_until: campaign.scheduled_at).perform_later(campaign_id)
        return
      end

      # Start sending the campaign
      if campaign.start_sending!
        Rails.logger.info("[SendScheduledJob] Campaign #{campaign_id} started sending")

        # Enqueue the job to create campaign_sends and start individual sends
        Campaigns::EnqueueSendingJob.perform_later(campaign_id)
      else
        Rails.logger.error("[SendScheduledJob] Failed to start campaign #{campaign_id}")
      end
    end
  end
end
