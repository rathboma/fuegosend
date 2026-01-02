module RiskManagement
  class ProcessQueuedCampaignJob < ApplicationJob
    queue_as :default

    # This job runs every minute via recurring_job configuration
    # Processes campaigns that have been queued for 30+ minutes

    def perform
      # Find all campaigns queued for review that have passed the 30-minute cooldown
      Campaign.queued_for_review
        .where("queued_at <= ?", 30.minutes.ago)
        .find_each do |campaign|

          begin
            campaign.process_after_cooldown!
            Rails.logger.info "Processed queued campaign #{campaign.id} after cooldown"
          rescue => e
            Rails.logger.error "Failed to process queued campaign #{campaign.id}: #{e.message}"
            # Don't halt processing of other campaigns
          end
        end
    end
  end
end
