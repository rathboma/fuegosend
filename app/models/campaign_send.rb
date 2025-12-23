class CampaignSend < ApplicationRecord
  belongs_to :campaign
  belongs_to :subscriber
  has_many :campaign_clicks, dependent: :destroy

  validates :status, inclusion: { in: %w[pending sending sent failed bounced complained] }

  # Scopes
  scope :pending, -> { where(status: "pending") }
  scope :sent, -> { where(status: "sent") }
  scope :failed, -> { where(status: "failed") }
  scope :delivered, -> { where.not(delivered_at: nil) }
  scope :bounced, -> { where(status: "bounced") }
  scope :complained, -> { where(status: "complained") }
  scope :opened, -> { where.not(opened_at: nil) }
  scope :clicked, -> { where.not(first_clicked_at: nil) }

  # Track as sent
  def mark_sent!(message_id)
    update!(
      status: "sent",
      ses_message_id: message_id,
      sent_at: Time.current
    )
    campaign.increment!(:sent_count)
  end

  # Track delivery
  def mark_delivered!
    return if delivered_at.present? # Already marked as delivered

    update!(delivered_at: Time.current)
    campaign.increment!(:delivered_count)
  end

  # Track bounce
  def mark_bounced!(bounce_type, reason = nil)
    update!(
      status: "bounced",
      bounced_at: Time.current,
      bounce_type: bounce_type,
      bounce_reason: reason
    )
    campaign.increment!(:bounced_count)

    # Update subscriber status for permanent bounces
    subscriber.mark_bounced! if bounce_type == "permanent"
  end

  # Track complaint
  def mark_complained!
    update!(
      status: "complained",
      complained_at: Time.current
    )
    campaign.increment!(:complained_count)
    subscriber.mark_complained!
  end

  # Track open
  def track_open!
    transaction do
      if opened_at.nil?
        update!(opened_at: Time.current)
        campaign.increment!(:opened_count)
      end
      increment!(:open_count)
    end
  end

  # Track click
  def track_click!(campaign_link)
    transaction do
      if first_clicked_at.nil?
        update!(first_clicked_at: Time.current)
        campaign.increment!(:clicked_count)
      end
      increment!(:click_count)

      campaign_clicks.create!(
        campaign_link: campaign_link,
        clicked_at: Time.current
      )
    end
  end

  # Track unsubscribe
  def track_unsubscribe!
    return if unsubscribed_at.present?

    update!(unsubscribed_at: Time.current)
    campaign.increment!(:unsubscribed_count)
    subscriber.unsubscribe!
  end

  # Mark as failed (for retrying)
  def mark_failed!(next_retry_delay = nil)
    attrs = {
      status: "failed",
      retry_count: retry_count + 1
    }

    if next_retry_delay
      attrs[:next_retry_at] = next_retry_delay.from_now
    end

    update!(attrs)
  end

  # Check if ready for retry
  def ready_for_retry?
    status == "failed" &&
      retry_count < 5 &&
      next_retry_at.present? &&
      next_retry_at <= Time.current
  end

  # Reset for retry
  def reset_for_retry!
    update!(status: "pending")
  end
end
