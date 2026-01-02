class CampaignMailer < ApplicationMailer
  default from: -> { "FuegoMail <noreply@#{Rails.application.config.action_mailer.default_url_options[:host] || 'fuegomail.com'}>" }

  def sending_started(campaign, user)
    @campaign = campaign
    @user = user
    @account = campaign.account

    mail(
      to: user.email,
      subject: "Campaign \"#{campaign.name}\" is now sending"
    )
  end

  def sending_completed(campaign, user)
    @campaign = campaign
    @user = user
    @account = campaign.account
    @stats = {
      total_recipients: campaign.total_recipients,
      sent_count: campaign.sent_count,
      delivered_count: campaign.delivered_count,
      opened_count: campaign.opened_count,
      clicked_count: campaign.clicked_count,
      open_rate: campaign.open_rate,
      click_rate: campaign.click_rate
    }

    mail(
      to: user.email,
      subject: "Campaign \"#{campaign.name}\" completed - #{campaign.sent_count} emails sent"
    )
  end

  def sending_failed(campaign, user, error_details)
    @campaign = campaign
    @user = user
    @account = campaign.account
    @error_details = error_details
    @stats = {
      total_recipients: campaign.total_recipients,
      sent_count: campaign.sent_count,
      failed_count: campaign.failed_count,
      failure_rate: campaign.failure_rate
    }

    mail(
      to: user.email,
      subject: "Campaign \"#{campaign.name}\" paused - Action required"
    )
  end

  def quota_exceeded(campaign, user)
    @campaign = campaign
    @user = user
    @account = campaign.account
    @quota_info = {
      sent_last_24_hours: @account.ses_sent_last_24_hours,
      max_24_hour_send: @account.ses_max_24_hour_send,
      quota_percent: @account.ses_quota_percent_used,
      reset_at: @account.ses_quota_reset_at
    }

    mail(
      to: user.email,
      subject: "Campaign \"#{campaign.name}\" paused - SES quota exceeded"
    )
  end
end
