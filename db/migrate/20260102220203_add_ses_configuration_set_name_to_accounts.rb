class AddSesConfigurationSetNameToAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :accounts, :ses_configuration_set_name, :string
  end
end
