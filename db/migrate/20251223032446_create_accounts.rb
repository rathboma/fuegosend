class CreateAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :accounts do |t|
      t.string :name, null: false
      t.string :subdomain, null: false
      t.string :encrypted_aws_access_key_id
      t.string :encrypted_aws_secret_access_key
      t.string :aws_region, default: "us-east-1"

      # SES sending limits (updated via SES API)
      t.integer :ses_max_send_rate, default: 1
      t.integer :ses_max_24_hour_send, default: 200
      t.integer :ses_sent_last_24_hours, default: 0
      t.datetime :ses_quota_reset_at

      # Account status
      t.boolean :active, default: true, null: false
      t.datetime :paused_at

      t.timestamps
    end

    add_index :accounts, :subdomain, unique: true
    add_index :accounts, :active
  end
end
