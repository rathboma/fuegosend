class CreateCampaignLinks < ActiveRecord::Migration[8.1]
  def change
    create_table :campaign_links do |t|
      t.references :campaign, null: false, foreign_key: true
      t.string :original_url, null: false
      t.string :token, null: false
      t.integer :click_count, default: 0, null: false
      t.integer :unique_click_count, default: 0, null: false

      t.timestamps
    end

    add_index :campaign_links, [:campaign_id, :token], unique: true
  end
end
