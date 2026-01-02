module Campaigns
  class RetryFailedJob < ApplicationJob
    queue_as :emails

    # Retry with exponential backoff
    retry_on StandardError, wait: :exponentially_longer, attempts: 3

    def perform(campaign_send_id)
      campaign_send = CampaignSend.find(campaign_send_id)
      campaign = campaign_send.campaign

      # Only retry if campaign send is ready
      unless campaign_send.ready_for_retry?
        Rails.logger.info("[RetryFailedJob] CampaignSend #{campaign_send_id} not ready for retry")
        return
      end

      # Only retry if campaign is still sending
      unless campaign.sending?
        Rails.logger.info("[RetryFailedJob] Campaign #{campaign.id} is not sending (status: #{campaign.status})")
        return
      end

      # Reset to pending status
      campaign_send.reset_for_retry!

      Rails.logger.info("[RetryFailedJob] Retrying CampaignSend #{campaign_send_id} (attempt #{campaign_send.retry_count})")

      # Enqueue the send job again with account_id for queue routing and concurrency control
      Campaigns::SendEmailJob.perform_later(campaign_send_id, campaign.account_id)
    end
  end
end
