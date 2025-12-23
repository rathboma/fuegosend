class CreateSegments < ActiveRecord::Migration[8.1]
  def change
    create_table :segments do |t|
      t.references :account, null: false, foreign_key: true
      t.references :list, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description

      # Filter criteria stored as JSON
      t.json :criteria, default: []

      # Cache count for performance
      t.integer :estimated_subscribers_count, default: 0, null: false
      t.datetime :count_updated_at

      t.timestamps
    end

    add_index :segments, [:account_id, :list_id]
  end
end
