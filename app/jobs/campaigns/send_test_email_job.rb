module Campaigns
  class SendTestEmailJob < ApplicationJob
    queue_as :default

    # Retry on SES errors with exponential backoff
    retry_on Aws::SES::Errors::ServiceError, wait: :exponentially_longer, attempts: 3

    def perform(campaign_id, recipient_email)
      campaign = Campaign.find(campaign_id)

      # Send the test email
      sender = Ses::TestEmailSender.new(campaign, recipient_email)
      result = sender.send_email

      if result[:success]
        Rails.logger.info("[SendTestEmailJob] Test email sent for campaign #{campaign_id} to #{recipient_email} - Message ID: #{result[:message_id]}")
      else
        Rails.logger.error("[SendTestEmailJob] Failed to send test email for campaign #{campaign_id}: #{result[:error]}")
        # Re-raise to trigger retry
        raise StandardError, result[:error]
      end
    end
  end
end
