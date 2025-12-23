class CreateSubscribers < ActiveRecord::Migration[8.1]
  def change
    create_table :subscribers do |t|
      t.references :account, null: false, foreign_key: true
      t.string :email, null: false
      t.string :status, default: "active", null: false

      # Custom attributes (flexible JSON storage)
      t.json :attributes, default: {}

      # Tracking
      t.string :source
      t.string :ip_address
      t.datetime :confirmed_at
      t.datetime :unsubscribed_at
      t.datetime :bounced_at
      t.datetime :complained_at

      t.timestamps
    end

    add_index :subscribers, [:account_id, :email], unique: true
    add_index :subscribers, [:account_id, :status]
    add_index :subscribers, :email
  end
end
