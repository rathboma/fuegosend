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
end
