class AddSlugToImages < ActiveRecord::Migration[8.1]
  def change
    add_column :images, :slug, :string
    add_index :images, :slug, unique: true
  end
end
