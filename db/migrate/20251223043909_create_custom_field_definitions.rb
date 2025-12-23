class CreateCustomFieldDefinitions < ActiveRecord::Migration[8.1]
  def change
    create_table :custom_field_definitions do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name, null: false
      t.string :field_type, default: "text", null: false
      t.text :description
      t.boolean :required, default: false, null: false
      t.json :validation_rules, default: {}

      t.timestamps
    end

    add_index :custom_field_definitions, [:account_id, :name], unique: true
  end
end
