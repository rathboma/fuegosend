class CreateTemplates < ActiveRecord::Migration[8.1]
  def change
    create_table :templates do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.text :html_content
      t.text :markdown_content
      t.boolean :is_default, default: false, null: false

      t.timestamps
    end

    add_index :templates, [:account_id, :name]
  end
end
