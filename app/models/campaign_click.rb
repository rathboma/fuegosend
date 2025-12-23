class CampaignClick < ApplicationRecord
  belongs_to :campaign_send
  belongs_to :campaign_link

  validates :clicked_at, presence: true

  # Scopes
  scope :recent, -> { order(clicked_at: :desc) }
  scope :by_link, ->(campaign_link) { where(campaign_link: campaign_link) }
  scope :by_campaign_send, ->(campaign_send) { where(campaign_send: campaign_send) }
  scope :in_date_range, ->(start_date, end_date) {
    where(clicked_at: start_date.beginning_of_day..end_date.end_of_day)
  }

  # Get the campaign associated with this click
  def campaign
    campaign_send.campaign
  end

  # Get the subscriber who clicked
  def subscriber
    campaign_send.subscriber
  end

  # Get click details
  def details
    {
      subscriber_email: subscriber.email,
      clicked_at: clicked_at,
      url: campaign_link.original_url,
      ip_address: ip_address,
      user_agent: user_agent
    }
  end

  # Parse user agent to extract browser/device info
  def browser_info
    return nil if user_agent.blank?

    # Simple user agent parsing (can be enhanced with a gem like browser)
    case user_agent
    when /Chrome/
      "Chrome"
    when /Firefox/
      "Firefox"
    when /Safari/
      "Safari"
    when /Edge/
      "Edge"
    when /MSIE|Trident/
      "Internet Explorer"
    else
      "Other"
    end
  end

  def device_type
    return nil if user_agent.blank?

    case user_agent
    when /Mobile|Android|iPhone|iPad/
      "Mobile"
    when /Tablet/
      "Tablet"
    else
      "Desktop"
    end
  end
end
