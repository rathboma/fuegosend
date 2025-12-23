class CampaignLink < ApplicationRecord
  belongs_to :campaign
  has_many :campaign_clicks, dependent: :destroy

  validates :original_url, presence: true
  validates :token, presence: true, uniqueness: { scope: :campaign_id }

  before_validation :generate_token, on: :create

  # Get or create a link for a campaign
  def self.find_or_create_for_url(campaign, url)
    find_or_create_by!(campaign: campaign, original_url: url) do |link|
      link.token = generate_unique_token(campaign)
    end
  end

  # Generate tracking URL
  def tracking_url(base_url)
    "#{base_url}/t/c/#{token}"
  end

  # Track a click
  def track_click!(campaign_send, ip_address: nil, user_agent: nil)
    transaction do
      # Check if this is a unique click (first click from this campaign_send)
      is_unique = campaign_clicks.where(campaign_send: campaign_send).none?

      # Increment counters
      increment!(:click_count)
      increment!(:unique_click_count) if is_unique

      # Create click record
      campaign_clicks.create!(
        campaign_send: campaign_send,
        ip_address: ip_address,
        user_agent: user_agent,
        clicked_at: Time.current
      )
    end
  end

  # Get click rate for this link
  def click_rate
    return 0 if campaign.delivered_count.zero?
    ((unique_click_count.to_f / campaign.delivered_count) * 100).round(2)
  end

  # Get total clicks from unique subscribers
  def unique_clicker_count
    campaign_clicks.select(:campaign_send_id).distinct.count
  end

  private

  def generate_token
    self.token ||= self.class.generate_unique_token(campaign)
  end

  def self.generate_unique_token(campaign)
    loop do
      token = SecureRandom.urlsafe_base64(12)
      break token unless campaign.campaign_links.exists?(token: token)
    end
  end
end
