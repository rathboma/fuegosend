class DashboardController < ApplicationController
  before_action :authenticate_user!

  def index
    @stats = {
      total_lists: current_account.lists.count,
      total_subscribers: current_account.subscribers.where(status: 'active').count,
      total_campaigns: current_account.campaigns.count,
      campaigns_sending: current_account.campaigns.where(status: 'sending').count,
      campaigns_scheduled: current_account.campaigns.where(status: 'scheduled').count
    }

    # Recent campaigns
    @recent_campaigns = current_account.campaigns
                                      .order(created_at: :desc)
                                      .limit(5)

    # SES quota info
    @ses_quota = {
      sent_today: current_account.ses_sent_last_24_hours,
      max_daily: current_account.ses_max_24_hour_send,
      max_rate: current_account.ses_max_send_rate,
      percent_used: current_account.ses_quota_percent_used
    }
  end

  private

  def current_account
    @current_account ||= current_user.account
  end
  helper_method :current_account
end
