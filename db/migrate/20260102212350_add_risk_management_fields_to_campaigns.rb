class AddRiskManagementFieldsToCampaigns < ActiveRecord::Migration[8.1]
  def change
    add_column :campaigns, :queued_at, :datetime, comment: "Timestamp when campaign entered queued_for_review state (30-min cooldown)"
    add_column :campaigns, :canary_started_at, :datetime, comment: "Timestamp when canary batch was sent (30-min analysis period)"
    add_column :campaigns, :canary_send_ids, :text, comment: "JSON array of campaign_send IDs that were part of canary batch"
    add_column :campaigns, :suspension_reason, :string, comment: "Reason why campaign was suspended (bounce rate, complaint rate, etc)"
  end
end
