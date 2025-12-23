class CreateCampaignClicks < ActiveRecord::Migration[8.1]
  def change
    create_table :campaign_clicks do |t|
      t.references :campaign_send, null: false, foreign_key: true
      t.references :campaign_link, null: false, foreign_key: true
      t.string :ip_address
      t.string :user_agent
      t.datetime :clicked_at, null: false

      t.timestamps
    end

    add_index :campaign_clicks, [:campaign_send_id, :campaign_link_id]
  end
end
