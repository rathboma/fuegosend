class CreateWebhookEndpoints < ActiveRecord::Migration[8.1]
  def change
    create_table :webhook_endpoints do |t|
      t.references :account, null: false, foreign_key: true
      t.string :endpoint_type, null: false
      t.string :sns_topic_arn
      t.string :webhook_secret
      t.boolean :active, default: true, null: false

      t.timestamps
    end

    add_index :webhook_endpoints, [:account_id, :endpoint_type]
  end
end
