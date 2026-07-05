class CreateComments < ActiveRecord::Migration[8.1]
  def change
    create_table :comments do |t|
      t.references :post, null: false, foreign_key: true
      t.string :author_name, null: false, limit: 30
      t.text :body, null: false
      t.string :ip_address

      t.timestamps
    end

    add_index :comments, :created_at
    add_index :comments, :ip_address
  end
end
