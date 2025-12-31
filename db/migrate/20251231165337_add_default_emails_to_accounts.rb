class AddDefaultEmailsToAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :accounts, :default_from_email, :string
    add_column :accounts, :default_reply_to_email, :string
  end
end
