class CreateImages < ActiveRecord::Migration[8.1]
  def change
    create_table :images do |t|
      t.references :account, null: false, foreign_key: true

      t.timestamps
    end
  end
end
