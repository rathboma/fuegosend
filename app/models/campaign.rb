class Campaign < ApplicationRecord
  belongs_to :account
  belongs_to :list
  belongs_to :segment, optional: true
  belongs_to :template, optional: true

  has_many :campaign_sends, dependent: :destroy
  has_many :campaign_links, dependent: :destroy
  has_many :subscribers, through: :campaign_sends

  validates :name, :subject, :from_name, :from_email, presence: true
  validates :status, inclusion: { in: %w[draft scheduled queued_for_review canary_processing approved sending sent paused suspended cancelled] }

  # Serialize canary_send_ids as JSON array
  serialize :canary_send_ids, coder: JSON

  # Set default email values from account
  after_initialize :set_default_emails, if: :new_record?

  # Scopes
  scope :draft, -> { where(status: "draft") }
  scope :scheduled, -> { where(status: "scheduled") }
  scope :queued_for_review, -> { where(status: "queued_for_review") }
  scope :canary_processing, -> { where(status: "canary_processing") }
  scope :approved, -> { where(status: "approved") }
  scope :sending, -> { where(status: "sending") }
  scope :sent, -> { where(status: "sent") }
  scope :paused, -> { where(status: "paused") }
  scope :suspended, -> { where(status: "suspended") }

  # State checks
  def draft?
    status == "draft"
  end

  def scheduled?
    status == "scheduled"
  end

  def queued_for_review?
    status == "queued_for_review"
  end

  def canary_processing?
    status == "canary_processing"
  end

  def approved?
    status == "approved"
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

  def suspended?
    status == "suspended"
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

    # Free plan accounts go through sandbox workflow with 30-min cooldown
    if account.requires_sandbox_workflow?
      return queue_for_review!
    end

    # Paid plans go straight to sending
    transaction do
      update!(
        status: "sending",
        started_sending_at: Time.current
      )

      # Refresh SES quota before starting to ensure we have latest limits
      # This is async but will complete quickly before emails start sending
      account.refresh_ses_quota!

      # Create campaign_sends for all recipients
      # Use async for large campaigns (>1000 recipients)
      estimated_count = recipients.count
      if estimated_count > 1000
        create_campaign_sends_async!
        # Job will call Campaigns::EnqueueSendingJob when done
      else
        create_campaign_sends!

        # Notify campaign creator
        notify_sending_started!

        # Enqueue sending jobs
        Campaigns::EnqueueSendingJob.perform_later(id)
      end
    end

    true
  end

  # Queue campaign for review (sandbox workflow for free plan)
  def queue_for_review!
    return false unless can_send?

    update!(
      status: "queued_for_review",
      queued_at: Time.current
    )

    # Background job will process after 30-minute cooldown
    # RiskManagement::ProcessQueuedCampaignJob runs every minute

    true
  end

  # Process queued campaign after cooldown period (30 minutes)
  def process_after_cooldown!
    return false unless queued_for_review?
    return false unless queued_at.present? && queued_at <= 30.minutes.ago

    # Refresh SES quota before starting
    account.refresh_ses_quota!

    # Create campaign_sends for all recipients
    # Use async for large campaigns (>1000 recipients)
    estimated_count = recipients.count
    if estimated_count > 1000
      create_campaign_sends_async!
      # Job will call continue_after_preparation! when done
    else
      create_campaign_sends!
      continue_after_preparation!
    end

    true
  end

  # Continue workflow after campaign sends are prepared
  def continue_after_preparation!
    # Check if list is large enough to warrant canary testing
    if total_recipients > 500
      # Send canary batch (100 random contacts)
      send_canary_batch!
    else
      # Small list, skip canary and go straight to approved
      update!(status: "approved")
      start_full_send!
    end
  end

  # Send canary batch to 100 random subscribers
  def send_canary_batch!
    # Select 100 random campaign_sends
    canary_batch = campaign_sends.pending.order("RANDOM()").limit(100)
    canary_ids = canary_batch.pluck(:id)

    update!(
      status: "canary_processing",
      canary_started_at: Time.current,
      canary_send_ids: canary_ids
    )

    # Notify that canary is being sent
    notify_sending_started!

    # Enqueue sending jobs for canary batch only
    canary_batch.each do |campaign_send|
      Campaigns::SendEmailJob.perform_later(campaign_send.id)
    end

    true
  end

  # Analyze canary batch results after 30-minute analysis period
  def analyze_canary_results!
    return false unless canary_processing?
    return false unless canary_started_at.present? && canary_started_at <= 30.minutes.ago

    canary_sends = campaign_sends.where(id: canary_send_ids)
    total_canary = canary_sends.count

    return false if total_canary.zero?

    # Count failures
    bounced = canary_sends.where(status: "bounced", bounce_type: "permanent").count
    complained = canary_sends.where(status: "complained").count

    # Calculate rates
    bounce_rate = (bounced.to_f / total_canary * 100).round(2)
    complaint_rate = (complained.to_f / total_canary * 100).round(2)

    # Decision thresholds
    if bounce_rate > 5.0
      suspend_campaign!("High bounce rate in canary batch: #{bounce_rate}% (threshold: 5%)")
      return false
    elsif complaint_rate > 1.0
      suspend_campaign!("High complaint rate in canary batch: #{complaint_rate}% (threshold: 1%)")
      return false
    else
      # Passed canary test, approve and send remaining
      update!(status: "approved")
      start_full_send!
      return true
    end
  end

  # Start sending to all remaining recipients (after canary approval)
  def start_full_send!
    update!(
      status: "sending",
      started_sending_at: Time.current
    )

    # Enqueue sending jobs for remaining (non-canary) recipients
    remaining_sends = if canary_send_ids.present?
      campaign_sends.pending.where.not(id: canary_send_ids)
    else
      campaign_sends.pending
    end

    # Enqueue in batches
    Campaigns::EnqueueSendingJob.perform_later(id)

    true
  end

  # Suspend campaign due to quality issues
  def suspend_campaign!(reason)
    update!(
      status: "suspended",
      suspension_reason: reason
    )

    # Notify account owners/admins
    notify_sending_failed!(reason)

    true
  end

  # Check if campaign should be killed (emergency kill-switch during sending)
  def check_kill_switch!
    return false unless sending?

    # Only check after minimum sample size (50 emails sent)
    sent_emails = campaign_sends.where(status: ["delivered", "bounced", "complained"]).count
    return false if sent_emails < 50

    # Check cumulative stats for campaign
    hard_bounces = campaign_sends.where(status: "bounced", bounce_type: "permanent").count
    complaints = campaign_sends.where(status: "complained").count

    # Calculate percentage rates
    bounce_rate = (hard_bounces.to_f / sent_emails * 100).round(2)
    complaint_rate = (complaints.to_f / sent_emails * 100).round(2)

    # Plan-based thresholds (Free plan is more strict, paid plans more lenient)
    if account.plan_free?
      # Free plan: 8% bounce rate OR 0.5% complaint rate
      if bounce_rate > 8.0
        suspend_campaign!("Emergency stop: #{bounce_rate}% bounce rate (Free plan threshold: 8%)")
        return true
      elsif complaint_rate > 0.5
        suspend_campaign!("Emergency stop: #{complaint_rate}% complaint rate (Free plan threshold: 0.5%)")
        return true
      end
    else
      # Paid plans: 15% bounce rate OR 1% complaint rate (less aggressive)
      if bounce_rate > 15.0
        suspend_campaign!("Emergency stop: #{bounce_rate}% bounce rate (threshold: 15%)")
        return true
      elsif complaint_rate > 1.0
        suspend_campaign!("Emergency stop: #{complaint_rate}% complaint rate (threshold: 1%)")
        return true
      end
    end

    false
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

  # Create campaign_sends for all recipients (synchronous - for small campaigns)
  def create_campaign_sends!
    recipients.find_each(batch_size: 1000) do |subscriber|
      campaign_sends.create!(subscriber: subscriber)
    end

    update!(total_recipients: campaign_sends.count)
  end

  # Create campaign_sends asynchronously with progress tracking
  def create_campaign_sends_async!
    Campaigns::CreateCampaignSendsJob.perform_later(id)
  end

  # Check if campaign sends are being prepared
  def preparing_sends?
    preparation_progress < 100 && sends_created_count < total_recipients
  end

  # Check if preparation is complete
  def preparation_complete?
    preparation_progress == 100 && sends_created_count == total_recipients
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

  # Notification methods - send to account owners and admins
  def notify_sending_started!
    account.users.where(role: %w[owner admin]).find_each do |user|
      CampaignMailer.sending_started(self, user).deliver_later
    end
  end

  def notify_sending_completed!
    account.users.where(role: %w[owner admin]).find_each do |user|
      CampaignMailer.sending_completed(self, user).deliver_later
    end
  end

  def notify_sending_failed!(error_details)
    account.users.where(role: %w[owner admin]).find_each do |user|
      CampaignMailer.sending_failed(self, user, error_details).deliver_later
    end
  end

  def notify_quota_exceeded!
    account.users.where(role: %w[owner admin]).find_each do |user|
      CampaignMailer.quota_exceeded(self, user).deliver_later
    end
  end

  def set_default_emails
    return unless account.present?
    self.from_email ||= account.default_from_email
    self.reply_to_email ||= account.default_reply_to_email
  end
end
