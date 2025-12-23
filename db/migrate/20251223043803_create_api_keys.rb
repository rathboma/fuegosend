class CreateApiKeys < ActiveRecord::Migration[8.1]
  def change
    create_table :api_keys do |t|
      t.references :account, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :token_digest, null: false
      t.string :last_4, null: false
      t.datetime :last_used_at
      t.datetime :expires_at
      t.boolean :active, default: true, null: false

      t.timestamps
    end

    add_index :api_keys, :token_digest, unique: true
    add_index :api_keys, [:account_id, :active]
  end
end
