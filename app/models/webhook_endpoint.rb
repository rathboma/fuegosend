class WebhookEndpoint < ApplicationRecord
  belongs_to :account

  validates :endpoint_type, presence: true, inclusion: { in: %w[bounce complaint delivery] }
  validates :endpoint_type, uniqueness: { scope: :account_id }

  # Generate a webhook secret on creation
  before_create :generate_webhook_secret

  private

  def generate_webhook_secret
    self.webhook_secret ||= SecureRandom.hex(32)
  end
end
