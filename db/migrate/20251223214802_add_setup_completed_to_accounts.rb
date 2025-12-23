class AddSetupCompletedToAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :accounts, :setup_completed, :boolean, default: false, null: false
  end
end
