module RiskManagement
  class MonitorActiveCampaignsJob < ApplicationJob
    queue_as :default

    # This job runs every 30 seconds via recurring_job configuration
    # Monitors all active sending campaigns for emergency kill-switch triggers
    # Applies to ALL plans (Free and Paid)

    def perform
      # Find all campaigns currently in sending state
      Campaign.sending.find_each do |campaign|
        begin
          triggered = campaign.check_kill_switch!

          if triggered
            Rails.logger.warn "Emergency kill-switch triggered for campaign #{campaign.id}: #{campaign.suspension_reason}"
          end
        rescue => e
          Rails.logger.error "Failed to check kill-switch for campaign #{campaign.id}: #{e.message}"
          # Don't halt monitoring of other campaigns
        end
      end
    end
  end
end
