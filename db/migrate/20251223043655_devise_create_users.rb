# frozen_string_literal: true

class DeviseCreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      # Multi-tenant relationship
      t.references :account, null: false, foreign_key: true

      ## Database authenticatable
      t.string :email,              null: false, default: ""
      t.string :encrypted_password, null: false, default: ""

      ## User details
      t.string :first_name
      t.string :last_name
      t.string :role, default: "member", null: false

      ## Recoverable
      t.string   :reset_password_token
      t.datetime :reset_password_sent_at

      ## Rememberable
      t.datetime :remember_created_at

      ## Trackable
      t.integer  :sign_in_count, default: 0, null: false
      t.datetime :current_sign_in_at
      t.datetime :last_sign_in_at
      t.string   :current_sign_in_ip
      t.string   :last_sign_in_ip

      ## Notification preferences
      t.boolean :daily_summary_enabled, default: true, null: false
      t.boolean :notify_campaign_start, default: true, null: false
      t.boolean :notify_campaign_complete, default: true, null: false
      t.boolean :notify_campaign_errors, default: true, null: false

      t.timestamps null: false
    end

    add_index :users, [:account_id, :email], unique: true
    add_index :users, :reset_password_token, unique: true
  end
end
