class AddBrandLogoToAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :accounts, :brand_logo, :string
  end
end
