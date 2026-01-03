class AddPreparationTrackingToCampaigns < ActiveRecord::Migration[8.1]
  def change
    add_column :campaigns, :preparation_progress, :integer, default: 0, null: false
    add_column :campaigns, :sends_created_count, :integer, default: 0, null: false
  end
end
