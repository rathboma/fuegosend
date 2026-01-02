class Campaign < ApplicationRecord
  belongs_to :account
  belongs_to :list
  belongs_to :segment, optional: true
  belongs_to :template, optional: true

  has_many :campaign_sends, dependent: :destroy
  has_many :campaign_links, dependent: :destroy
  has_many :subscribers, through: :campaign_sends

  validates :name, :subject, :from_name, :from_email, presence: true
  validates :status, inclusion: { in: %w[draft scheduled sending sent paused cancelled] }

  # Set default email values from account
  after_initialize :set_default_emails, if: :new_record?

  # Scopes
  scope :draft, -> { where(status: "draft") }
  scope :scheduled, -> { where(status: "scheduled") }
  scope :sending, -> { where(status: "sending") }
  scope :sent, -> { where(status: "sent") }
  scope :paused, -> { where(status: "paused") }

  # State checks
  def draft?
    status == "draft"
  end

  def scheduled?
    status == "scheduled"
  end

  def sending?
    status == "sending"
  end

  def sent?
    status == "sent"
  end

  def paused?
    status == "paused"
  end

  # Schedule campaign for sending
  def schedule!(scheduled_time)
    return false unless draft?

    update!(
      status: "scheduled",
      scheduled_at: scheduled_time
    )

    # Enqueue job to send at scheduled time
    Campaigns::SendScheduledJob.set(wait_until: scheduled_at).perform_later(id)
    true
  end

  # Start sending campaign
  def start_sending!
    return false unless can_send?

    transaction do
      update!(
        status: "sending",
        started_sending_at: Time.current
      )

      # Refresh SES quota before starting to ensure we have latest limits
      # This is async but will complete quickly before emails start sending
      account.refresh_ses_quota!

      # Create campaign_sends for all recipients
      create_campaign_sends!

      # Notify campaign creator (will implement with mailer)
      notify_sending_started!

      # Enqueue sending jobs
      Campaigns::EnqueueSendingJob.perform_later(id)
    end

    true
  end

  # Pause campaign
  def pause!(reason: nil)
    return false unless sending?

    update!(status: "paused")

    # Notify based on reason
    case reason
    when :quota_exceeded
      notify_quota_exceeded!
    when :too_many_failures
      notify_sending_failed!("Too many send failures")
    end

    true
  end

  # Resume paused campaign
  def resume!
    return false unless paused?

    update!(status: "sending")
    Campaigns::EnqueueSendingJob.perform_later(id)
    true
  end

  # Mark campaign as complete
  def complete_sending!
    return false unless sending?

    update!(
      status: "sent",
      finished_sending_at: Time.current
    )

    notify_sending_completed!
    true
  end

  # Cancel campaign
  def cancel!
    return false unless draft? || scheduled?

    update!(status: "cancelled")
    true
  end

  # Get recipients (segment or all list subscribers)
  def recipients
    if segment
      segment.matching_subscribers
    else
      list.active_subscribers
    end
  end

  # Create campaign_sends for all recipients
  def create_campaign_sends!
    recipients.find_each(batch_size: 1000) do |subscriber|
      campaign_sends.create!(subscriber: subscriber)
    end

    update!(total_recipients: campaign_sends.count)
  end

  # Calculate stats
  def percent_complete
    return 0 if total_recipients.zero?
    ((sent_count.to_f / total_recipients) * 100).round(1)
  end

  def open_rate
    return 0 if delivered_count.zero?
    ((opened_count.to_f / delivered_count) * 100).round(2)
  end

  def click_rate
    return 0 if delivered_count.zero?
    ((clicked_count.to_f / delivered_count) * 100).round(2)
  end

  def bounce_rate
    return 0 if sent_count.zero?
    ((bounced_count.to_f / sent_count) * 100).round(2)
  end

  def failure_rate
    return 0 if total_recipients.zero?
    failed_count = campaign_sends.where(status: "failed").count
    ((failed_count.to_f / total_recipients) * 100).round(2)
  end

  def has_failures?
    campaign_sends.where(status: "failed").exists?
  end

  def failed_count
    campaign_sends.where(status: "failed").count
  end

  # Current send rate (emails per second) - estimated from last 5 minutes
  def current_send_rate
    return 0 unless sending?

    recent_sends = campaign_sends.where("sent_at >= ?", 5.minutes.ago).count
    (recent_sends / 300.0).round(1) # 300 seconds = 5 minutes
  end

  # Personalized body for a subscriber (using Mustache)
  def personalized_body_for(subscriber, campaign_send = nil)
    content = markdown_to_html(body_markdown)
    data = build_mustache_data(subscriber, campaign_send)

    # Render content using Mustache
    Mustache.render(content, data)
  end

  private

  def can_send?
    (draft? || scheduled?) && account.can_send_email?
  end

  def markdown_to_html(markdown)
    return "" if markdown.blank?
    Kramdown::Document.new(markdown).to_html
  end

  def build_mustache_data(subscriber, campaign_send = nil)
    data = {
      # Subscriber data
      email: subscriber.email,
      subscriber_email: subscriber.email,

      # Custom attributes (flatten for easier access)
      name: subscriber.get_attribute("name"),
      first_name: subscriber.get_attribute("first_name"),
      last_name: subscriber.get_attribute("last_name"),

      # Campaign data
      campaign_name: name,
      campaign_subject: subject,
      campaign_from_name: from_name,
      campaign_from_email: from_email,

      # Account data
      account_name: account.name,
      logo_url: account.brand_logo.presence || "/logo-placeholder.png",

      # URLs - generate real URL if campaign_send is provided
      unsubscribe_url: unsubscribe_url_for(campaign_send),

      # Other
      current_year: Time.current.year
    }.merge(flatten_custom_attributes(subscriber))
  end

  # Generate unsubscribe URL for a specific campaign send
  def unsubscribe_url_for(campaign_send)
    return "#unsubscribe" unless campaign_send

    # Generate tracking token for this campaign_send
    verifier = Rails.application.message_verifier(:campaign_tracking)
    token = verifier.generate(campaign_send.id)

    # Build URL with configured host
    host = Rails.application.config.action_mailer.default_url_options[:host] || 'localhost'
    port = Rails.application.config.action_mailer.default_url_options[:port]
    protocol = Rails.env.production? ? 'https' : 'http'

    url = "#{protocol}://#{host}"
    url += ":#{port}" if port && !Rails.env.production?
    url += "/unsubscribe/#{token}"

    url
  end

  # Flatten custom attributes for Mustache access
  # Converts subscriber.custom_attributes = {company: "Acme"} to {custom_company: "Acme"}
  def flatten_custom_attributes(subscriber)
    return {} unless subscriber.custom_attributes.is_a?(Hash)

    subscriber.custom_attributes.transform_keys { |key| "custom_#{key}".to_sym }
  end

  # Apply merge tags to arbitrary text content
  def apply_merge_tags(text, subscriber, campaign_send = nil)
    return text if text.blank?

    data = build_mustache_data(subscriber, campaign_send)
    Mustache.render(text, data)
  end

  # Notification methods (placeholders for now - will implement with mailer)
  def notify_sending_started!
    # Account owners and admins will be notified
    # CampaignMailer.sending_started(self, user).deliver_later
  end

  def notify_sending_completed!
    # CampaignMailer.sending_completed(self, user).deliver_later
  end

  def notify_sending_failed!(error_details)
    # CampaignMailer.sending_failed(self, user, error_details).deliver_later
  end

  def notify_quota_exceeded!
    # CampaignMailer.quota_exceeded(self, user).deliver_later
  end

  def set_default_emails
    return unless account.present?
    self.from_email ||= account.default_from_email
    self.reply_to_email ||= account.default_reply_to_email
  end
end
