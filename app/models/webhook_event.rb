class WebhookEvent < ApplicationRecord
  belongs_to :account

  validates :event_type, presence: true
  validates :event_type, inclusion: { in: %w[bounce complaint delivery open click] }

  # Scopes
  scope :unprocessed, -> { where(processed: false) }
  scope :processed, -> { where(processed: true) }
  scope :by_type, ->(type) { where(event_type: type) }

  # Mark as processed
  def mark_processed!
    update!(processed: true, processed_at: Time.current)
  end
end
