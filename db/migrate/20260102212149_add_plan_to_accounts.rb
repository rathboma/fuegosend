class AddPlanToAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :accounts, :plan, :integer, default: 0, null: false, comment: "Plan tier: 0=free, 1=starter, 2=pro, 3=agency"
  end
end
