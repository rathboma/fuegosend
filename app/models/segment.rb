class Segment < ApplicationRecord
  belongs_to :account
  belongs_to :list
  has_many :campaigns, dependent: :nullify

  validates :name, presence: true

  # Build dynamic query from criteria using the SegmentQueryBuilder service
  def matching_subscribers
    SegmentQueryBuilder.new(self).build
  end

  # Refresh the estimated count
  def refresh_count!
    count = matching_subscribers.count
    update!(
      estimated_subscribers_count: count,
      count_updated_at: Time.current
    )
  end

  # Check if count needs refreshing (older than 1 hour)
  def count_stale?
    count_updated_at.nil? || count_updated_at < 1.hour.ago
  end

  # Get count, refresh if stale
  def current_count
    refresh_count! if count_stale?
    estimated_subscribers_count
  end
end
