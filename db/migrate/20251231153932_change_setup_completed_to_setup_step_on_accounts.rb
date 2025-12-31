class ChangeSetupCompletedToSetupStepOnAccounts < ActiveRecord::Migration[8.1]
  def change
    # Remove old boolean column
    remove_column :accounts, :setup_completed, :boolean

    # Add new enum column
    add_column :accounts, :setup_step, :integer, default: 0, null: false
  end
end
