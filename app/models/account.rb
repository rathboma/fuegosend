class Account < ApplicationRecord
  has_many :users, dependent: :destroy
  has_many :api_keys, dependent: :destroy
  has_many :lists, dependent: :destroy
  has_many :subscribers, dependent: :destroy
  has_many :segments, dependent: :destroy
  has_many :campaigns, dependent: :destroy
  has_many :templates, dependent: :destroy
  has_many :custom_field_definitions, dependent: :destroy
  has_many :webhook_endpoints, dependent: :destroy
  has_many :webhook_events, dependent: :destroy

  # Encryption for AWS credentials
  encrypts :aws_access_key_id
  encrypts :aws_secret_access_key

  validates :name, presence: true
  validates :subdomain, presence: true, uniqueness: true,
            format: { with: /\A[a-z0-9-]+\z/, message: "only allows lowercase letters, numbers, and hyphens" }

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
