module Campaigns
  class EnqueueSendingJob < ApplicationJob
    queue_as :default

    # Retry with backoff if job fails
    retry_on StandardError, wait: :exponentially_longer, attempts: 5

    BATCH_SIZE = 100 # Number of sends to enqueue at once
    MAX_FAILURE_RATE = 10.0 # Pause campaign if failure rate exceeds 10%

    def perform(campaign_id)
      campaign = Campaign.find(campaign_id)
      account = campaign.account

      # Only process if campaign is in sending state
      unless campaign.sending?
        Rails.logger.info("[EnqueueSendingJob] Campaign #{campaign_id} is not sending (status: #{campaign.status})")
        return
      end

      # Check if account quota exceeded
      if account.ses_quota_exceeded?
        Rails.logger.warn("[EnqueueSendingJob] Campaign #{campaign_id} paused - quota exceeded")
        campaign.pause!(reason: :quota_exceeded)
        return
      end

      # Check for high failure rate
      if campaign.total_recipients > 100 && campaign.failure_rate > MAX_FAILURE_RATE
        Rails.logger.warn("[EnqueueSendingJob] Campaign #{campaign_id} paused - failure rate too high (#{campaign.failure_rate}%)")
        campaign.pause!(reason: :too_many_failures)
        return
      end

      # Find pending campaign sends
      pending_sends = campaign.campaign_sends.where(status: "pending").limit(BATCH_SIZE)

      if pending_sends.empty?
        # Check if all sends are complete
        if campaign.campaign_sends.where(status: %w[pending sending]).none?
          Rails.logger.info("[EnqueueSendingJob] Campaign #{campaign_id} completed - all sends processed")
          campaign.complete_sending!
        else
          # Still have sends in progress, check again later
          Rails.logger.info("[EnqueueSendingJob] Campaign #{campaign_id} - waiting for in-progress sends")
          self.class.set(wait: 30.seconds).perform_later(campaign_id)
        end
        return
      end

      # Enqueue individual send jobs with account_id for queue routing and concurrency control
      pending_sends.each do |campaign_send|
        Campaigns::SendEmailJob.perform_later(campaign_send.id, account.id)
      end

      Rails.logger.info("[EnqueueSendingJob] Campaign #{campaign_id} - enqueued #{pending_sends.count} sends")

      # Re-enqueue this job to process next batch
      # Add a small delay to avoid overwhelming the queue
      self.class.set(wait: 5.seconds).perform_later(campaign_id)
    end
  end
end
