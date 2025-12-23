class CreateCampaigns < ActiveRecord::Migration[8.1]
  def change
    create_table :campaigns do |t|
      t.references :account, null: false, foreign_key: true
      t.references :list, null: false, foreign_key: true
      t.references :segment, foreign_key: true
      t.references :template, foreign_key: true

      # Campaign details
      t.string :name, null: false
      t.string :subject, null: false
      t.string :from_name, null: false
      t.string :from_email, null: false
      t.string :reply_to_email

      # Content
      t.text :body_html
      t.text :body_markdown
      t.text :body_text

      # Status and scheduling
      t.string :status, default: "draft", null: false
      t.datetime :scheduled_at
      t.datetime :started_sending_at
      t.datetime :finished_sending_at

      # Statistics
      t.integer :total_recipients, default: 0, null: false
      t.integer :sent_count, default: 0, null: false
      t.integer :delivered_count, default: 0, null: false
      t.integer :bounced_count, default: 0, null: false
      t.integer :complained_count, default: 0, null: false
      t.integer :opened_count, default: 0, null: false
      t.integer :clicked_count, default: 0, null: false
      t.integer :unsubscribed_count, default: 0, null: false

      t.timestamps
    end

    add_index :campaigns, [:account_id, :status]
    add_index :campaigns, :scheduled_at
  end
end
