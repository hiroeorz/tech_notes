class AddNameEnToCategories < ActiveRecord::Migration[8.1]
  def change
    add_column :categories, :name_en, :string
  end
end
