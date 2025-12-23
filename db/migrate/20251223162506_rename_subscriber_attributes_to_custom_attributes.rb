class RenameSubscriberAttributesToCustomAttributes < ActiveRecord::Migration[8.1]
  def change
    rename_column :subscribers, :attributes, :custom_attributes
  end
end
