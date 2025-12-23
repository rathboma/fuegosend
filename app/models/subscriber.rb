class Subscriber < ApplicationRecord
  belongs_to :account
  has_many :list_subscriptions, dependent: :destroy
  has_many :lists, through: :list_subscriptions
  has_many :campaign_sends, dependent: :destroy

  validates :email, presence: true,
            format: { with: URI::MailTo::EMAIL_REGEXP },
            uniqueness: { scope: :account_id }
  validates :status, inclusion: { in: %w[active unsubscribed bounced complained] }

  # Scopes
  scope :active, -> { where(status: "active") }
  scope :unsubscribed, -> { where(status: "unsubscribed") }
  scope :bounced, -> { where(status: "bounced") }
  scope :complained, -> { where(status: "complained") }

  # Query by custom attributes (SQLite JSON support)
  scope :with_attribute, ->(key, value) {
    where("json_extract(custom_attributes, ?) = ?", "$.#{key}", value.to_json)
  }

  # Unsubscribe from all lists
  def unsubscribe!
    transaction do
      update!(status: "unsubscribed", unsubscribed_at: Time.current)
      list_subscriptions.where(status: "active").update_all(
        status: "unsubscribed",
        unsubscribed_at: Time.current
      )
    end
  end

  # Mark as bounced
  def mark_bounced!
    update!(status: "bounced", bounced_at: Time.current)
  end

  # Mark as complained
  def mark_complained!
    update!(status: "complained", complained_at: Time.current)
  end

  # Get custom attribute value
  def get_attribute(key)
    custom_attributes&.dig(key)
  end

  # Set custom attribute value
  def set_attribute(key, value)
    self.custom_attributes = (self.custom_attributes || {}).merge(key.to_s => value)
  end

  # Merge multiple custom attributes
  def merge_custom_attributes(attrs)
    self.custom_attributes = (self.custom_attributes || {}).merge(attrs.stringify_keys)
  end
end
