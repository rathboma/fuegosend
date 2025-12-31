class RenameEncryptedAwsColumnsOnAccounts < ActiveRecord::Migration[8.1]
  def change
    # Rails' encrypts method expects columns without the 'encrypted_' prefix
    rename_column :accounts, :encrypted_aws_access_key_id, :aws_access_key_id
    rename_column :accounts, :encrypted_aws_secret_access_key, :aws_secret_access_key
  end
end
