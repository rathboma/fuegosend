class CreateLists < ActiveRecord::Migration[8.1]
  def change
    create_table :lists do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.integer :subscribers_count, default: 0, null: false

      # Form settings
      t.boolean :enable_subscription_form, default: true, null: false
      t.text :form_success_message
      t.string :form_redirect_url
      t.boolean :double_opt_in, default: false, null: false

      t.timestamps
    end

    add_index :lists, [:account_id, :name]
  end
end
