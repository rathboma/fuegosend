class Account < ApplicationRecord
  has_many :users, dependent: :destroy
  has_many :api_keys, dependent: :destroy
  has_many :lists, dependent: :destroy
  has_many :subscribers, dependent: :destroy
  has_many :segments, dependent: :destroy
  has_many :campaigns, dependent: :destroy
  has_many :templates, dependent: :destroy
  has_many :images, dependent: :destroy
  has_many :custom_field_definitions, dependent: :destroy
  has_many :webhook_endpoints, dependent: :destroy
  has_many :webhook_events, dependent: :destroy

  # Logo attachment
  has_one_attached :logo

  # Encryption for AWS credentials
  encrypts :aws_access_key_id
  encrypts :aws_secret_access_key

  # Setup progress tracking
  enum :setup_step, {
    not_started: 0,
    account_details: 1,
    aws_credentials: 2,
    complete: 3
  }, prefix: true

  # Plan tiers for feature gating and risk management
  enum :plan, {
    free: 0,
    starter: 1,
    pro: 2,
    agency: 3
  }, prefix: true

  validates :name, presence: true
  validates :subdomain, presence: true, uniqueness: true,
            format: { with: /\A[a-z0-9-]+\z/, message: "only allows lowercase letters, numbers, and hyphens" }
  validates :default_from_email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP, message: "must be a valid email address" }
  validates :default_reply_to_email, format: { with: URI::MailTo::EMAIL_REGEXP, message: "must be a valid email address" }, allow_blank: true

  # Check if setup is complete
  def setup_complete?
    setup_step_complete?
  end

  # Determine which step user should see
  def current_setup_step
    return 1 if setup_step_not_started?
    return 2 if setup_step_account_details?
    return 3 if setup_step_aws_credentials?
    nil # Setup complete, no step to show
  end

  def aws_credentials_configured?
    aws_access_key_id.present? && aws_secret_access_key.present? && aws_region.present?
  end

  def logo_url
    if logo.attached?
      Rails.application.routes.url_helpers.rails_blob_url(logo, only_path: false)
    else
      brand_logo # Fallback to URL field
    end
  end

  # Check if account is paused
  def paused?
    paused_at.present?
  end

  # Pause the account
  def pause!
    update!(paused_at: Time.current)
  end

  # Unpause the account
  def unpause!
    update!(paused_at: nil)
  end

  # Check if account can send emails
  def can_send_email?
    active? && !paused? && !ses_quota_exceeded?
  end

  def ses_quota_exceeded?
    ses_sent_last_24_hours >= ses_max_24_hour_send
  end

  def ses_quota_nearly_exceeded?
    ses_quota_percent_used >= 80
  end

  def ses_quota_percent_used
    return 0 if ses_max_24_hour_send.zero?
    (ses_sent_last_24_hours.to_f / ses_max_24_hour_send * 100).round(1)
  end

  # Update SES sending limits from AWS
  def refresh_ses_quota!
    Ses::QuotaRefreshJob.perform_later(id)
  end

  # Get SES client
  def ses_client
    @ses_client ||= Aws::SES::Client.new(
      access_key_id: aws_access_key_id,
      secret_access_key: aws_secret_access_key,
      region: aws_region
    )
  end

  # Plan-based feature gating
  # Free plan uses sandbox workflow with delays and canary testing
  def requires_sandbox_workflow?
    plan_free?
  end

  # Free plan limited to 1 list/segment
  def max_lists
    plan_free? ? 1 : Float::INFINITY
  end

  def max_segments
    plan_free? ? 1 : Float::INFINITY
  end

  # Free plan has import throttling (30-minute validation delay)
  def requires_import_throttling?
    plan_free?
  end

  # Check if account can create more lists
  def can_create_list?
    lists.count < max_lists
  end

  # Check if account can create more segments
  def can_create_segment?
    segments.count < max_segments
  end

  # Get subscriber limits by plan
  def max_subscribers
    case plan.to_sym
    when :free then 500
    when :starter then 5_000
    when :pro then 25_000
    when :agency then Float::INFINITY
    end
  end

  # Get monthly email limits by plan
  def max_monthly_emails
    case plan.to_sym
    when :free then 2_500
    when :starter then 25_000
    when :pro then 125_000
    when :agency then Float::INFINITY
    end
  end

  # Check if account has reached subscriber limit
  def at_subscriber_limit?
    subscribers.active.count >= max_subscribers
  end

  # Tracking domain tier assignment
  def tracking_domain_tier
    case plan.to_sym
    when :free then 1  # Disposable pool
    when :starter, :pro then 2  # Premium shared domain
    when :agency then 3  # Custom CNAME support
    end
  end

  # Get the tracking domain for this account
  # Returns custom domain if set (Agency), otherwise returns tier-appropriate domain
  def get_tracking_domain
    # If custom domain set (Agency plan), use it
    return tracking_domain if tracking_domain.present?

    # Otherwise use tier-based defaults
    case tracking_domain_tier
    when 1
      # Free plan: Rotate through disposable domain pool
      # In production, this would be a pool of domains
      pool = ["links-a.fuegomail.com", "links-b.fuegomail.com", "links-c.fuegomail.com"]
      pool[id % pool.size]
    when 2
      # Starter/Pro: Premium shared domain
      "track.fuegomail.com"
    when 3
      # Agency: Should have custom domain set, fallback to premium
      "track.fuegomail.com"
    end
  end
end
