class CreateCampaignSends < ActiveRecord::Migration[8.1]
  def change
    create_table :campaign_sends do |t|
      t.references :campaign, null: false, foreign_key: true
      t.references :subscriber, null: false, foreign_key: true

      # SES tracking
      t.string :ses_message_id
      t.string :status, default: "pending", null: false

      # Tracking
      t.datetime :sent_at
      t.datetime :delivered_at
      t.datetime :bounced_at
      t.string :bounce_type
      t.text :bounce_reason
      t.datetime :complained_at
      t.datetime :opened_at
      t.integer :open_count, default: 0, null: false
      t.datetime :first_clicked_at
      t.integer :click_count, default: 0, null: false
      t.datetime :unsubscribed_at

      # Retry logic
      t.integer :retry_count, default: 0, null: false
      t.datetime :next_retry_at

      t.timestamps
    end

    add_index :campaign_sends, [:campaign_id, :subscriber_id], unique: true
    add_index :campaign_sends, [:campaign_id, :status]
    add_index :campaign_sends, :ses_message_id
    add_index :campaign_sends, [:status, :next_retry_at]
  end
end
