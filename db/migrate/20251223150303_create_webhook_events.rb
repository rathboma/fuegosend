class CreateWebhookEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :webhook_events do |t|
      t.references :account, null: false, foreign_key: true
      t.string :event_type, null: false
      t.json :payload
      t.boolean :processed, default: false, null: false
      t.datetime :processed_at

      t.timestamps
    end

    add_index :webhook_events, [:account_id, :processed]
    add_index :webhook_events, :event_type
  end
end
