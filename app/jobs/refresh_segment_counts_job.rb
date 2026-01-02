class RefreshSegmentCountsJob < ApplicationJob
  queue_as :default

  def perform
    # Find all segments with stale counts (older than 1 hour or never updated)
    stale_segments = Segment.where("count_updated_at IS NULL OR count_updated_at < ?", 1.hour.ago)

    stale_segments.find_each do |segment|
      begin
        segment.refresh_count!
        Rails.logger.info "Refreshed count for segment #{segment.id} (#{segment.name}): #{segment.estimated_subscribers_count} subscribers"
      rescue => e
        Rails.logger.error "Failed to refresh count for segment #{segment.id}: #{e.message}"
      end
    end
  end
end
