class CreateListSubscriptions < ActiveRecord::Migration[8.1]
  def change
    create_table :list_subscriptions do |t|
      t.references :list, null: false, foreign_key: true
      t.references :subscriber, null: false, foreign_key: true
      t.string :status, default: "active", null: false
      t.datetime :subscribed_at
      t.datetime :unsubscribed_at

      t.timestamps
    end

    add_index :list_subscriptions, [:list_id, :subscriber_id], unique: true
    add_index :list_subscriptions, [:subscriber_id, :list_id]
    add_index :list_subscriptions, [:list_id, :status]
  end
end
