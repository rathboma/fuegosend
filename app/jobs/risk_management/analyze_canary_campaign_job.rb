module RiskManagement
  class AnalyzeCanaryCampaignJob < ApplicationJob
    queue_as :default

    # This job runs every minute via recurring_job configuration
    # Analyzes canary batches that have been sent for 30+ minutes

    def perform
      # Find all campaigns in canary_processing that have passed the 30-minute analysis period
      Campaign.canary_processing
        .where("canary_started_at <= ?", 30.minutes.ago)
        .find_each do |campaign|

          begin
            result = campaign.analyze_canary_results!

            if result
              Rails.logger.info "Canary test passed for campaign #{campaign.id}, starting full send"
            else
              Rails.logger.warn "Canary test failed for campaign #{campaign.id}: #{campaign.suspension_reason}"
            end
          rescue => e
            Rails.logger.error "Failed to analyze canary for campaign #{campaign.id}: #{e.message}"
            # Don't halt processing of other campaigns
          end
        end
    end
  end
end
