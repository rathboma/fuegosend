module Ses
  class QuotaRefreshJob < ApplicationJob
    queue_as :default

    # Retry with exponential backoff
    retry_on StandardError, wait: :exponentially_longer, attempts: 5

    def perform(account_id = nil)
      if account_id
        # Refresh quota for specific account
        refresh_account_quota(account_id)
      else
        # Refresh quota for all active accounts
        refresh_all_accounts
      end
    end

    private

    def refresh_account_quota(account_id)
      account = Account.find(account_id)

      unless account.active?
        Rails.logger.info("[QuotaRefreshJob] Account #{account_id} is not active")
        return
      end

      quota_checker = Ses::QuotaChecker.new(account)
      result = quota_checker.refresh_quota!

      if result[:success]
        Rails.logger.info("[QuotaRefreshJob] Successfully refreshed quota for account #{account_id}")

        # Check if account was paused due to quota and can now resume
        if account.paused? && !account.ses_quota_exceeded?
          # Resume any paused campaigns
          account.campaigns.where(status: "paused").each do |campaign|
            campaign.resume!
            Rails.logger.info("[QuotaRefreshJob] Resumed campaign #{campaign.id}")
          end
        end
      else
        Rails.logger.error("[QuotaRefreshJob] Failed to refresh quota for account #{account_id}: #{result[:error]}")
      end
    rescue ActiveRecord::RecordNotFound
      Rails.logger.error("[QuotaRefreshJob] Account #{account_id} not found")
    rescue StandardError => e
      Rails.logger.error("[QuotaRefreshJob] Error refreshing quota for account #{account_id}: #{e.message}")
      raise # Re-raise to trigger retry
    end

    def refresh_all_accounts
      Account.where(active: true).find_each do |account|
        begin
          refresh_account_quota(account.id)
        rescue StandardError => e
          # Log error but continue with other accounts
          Rails.logger.error("[QuotaRefreshJob] Error refreshing account #{account.id}: #{e.message}")
        end
      end

      Rails.logger.info("[QuotaRefreshJob] Completed quota refresh for all accounts")
    end
  end
end
