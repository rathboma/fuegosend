module Campaigns
  class SendEmailJob < ApplicationJob
    # Use per-account queues for fair distribution across accounts
    # Workers configured to process "emails_account_*" pattern
    queue_as do
      account_id = arguments.second
      "emails_account_#{account_id}"
    end

    # Limit concurrent email sends per account based on their SES rate limit
    # - to: dynamically calculated as 70% of account's max_send_rate
    #   * Leaves 30% headroom to handle race conditions in rate limiter
    #   * New accounts (1/sec) → concurrency of 1
    #   * Free tier (14/sec) → concurrency of 9
    #   * Scales automatically as accounts request SES limit increases
    # - duration: 10.minutes is failsafe if job doesn't release semaphore
    # - key groups jobs by account_id for per-account limiting
    # - on_conflict: :block (default) queues jobs rather than discarding
    limits_concurrency to: ->(campaign_send_id, account_id) {
                         account = Account.find(account_id)
                         max_rate = account.ses_max_send_rate || 14
                         # Use 70% of max rate, minimum 1
                         [(max_rate * 0.7).to_i, 1].max
                       },
                       key: ->(campaign_send_id, account_id) { account_id },
                       duration: 10.minutes

    # Don't retry automatically - we handle retries manually in the service
    # This prevents duplicate sends
    discard_on StandardError do |job, error|
      Rails.logger.error("[SendEmailJob] Job failed: #{error.class.name} - #{error.message}")
    end

    def perform(campaign_send_id, account_id)
      campaign_send = CampaignSend.find(campaign_send_id)
      campaign = campaign_send.campaign
      account = campaign.account

      # Skip if campaign send is no longer pending
      unless campaign_send.status == "pending"
        Rails.logger.info("[SendEmailJob] CampaignSend #{campaign_send_id} already processed (status: #{campaign_send.status})")
        return
      end

      # Skip if campaign is no longer sending
      unless campaign.sending?
        Rails.logger.info("[SendEmailJob] Campaign #{campaign.id} is not sending (status: #{campaign.status})")
        return
      end

      # Check rate limits
      rate_limiter = Ses::RateLimiter.new(account)

      unless rate_limiter.can_send?
        wait_time = rate_limiter.wait_time

        if wait_time > 1.hour
          # Daily quota exceeded - pause campaign
          Rails.logger.warn("[SendEmailJob] Campaign #{campaign.id} quota exceeded, pausing")
          campaign.pause!(reason: :quota_exceeded)
          return
        else
          # Per-second rate limit - retry after wait time
          Rails.logger.info("[SendEmailJob] Rate limited, retrying in #{wait_time} seconds")
          self.class.set(wait: wait_time).perform_later(campaign_send_id, account_id)
          return
        end
      end

      # Increment rate limiter counter
      rate_limiter.increment!

      # Send the email
      email_sender = Ses::EmailSender.new(campaign_send)
      result = email_sender.send_email

      if result[:success]
        Rails.logger.info("[SendEmailJob] Successfully sent email #{campaign_send_id} - Message ID: #{result[:message_id]}")
      else
        Rails.logger.error("[SendEmailJob] Failed to send email #{campaign_send_id}: #{result[:error]}")

        # Check if we should retry
        if campaign_send.ready_for_retry?
          Rails.logger.info("[SendEmailJob] Scheduling retry for #{campaign_send_id}")
          Campaigns::RetryFailedJob.set(wait_until: campaign_send.next_retry_at)
                                   .perform_later(campaign_send_id)
        end
      end
    end
  end
end
