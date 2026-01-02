class AddTrackingDomainToAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :accounts, :tracking_domain, :string, comment: "Domain used for tracking links (tier-based for reputation isolation)"
  end
end
