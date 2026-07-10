class CreatePostTranslations < ActiveRecord::Migration[8.1]
  def change
    create_table :post_translations do |t|
      t.references :post, null: false, foreign_key: true
      t.string :locale, null: false
      t.string :title, null: false
      t.text :body, null: false
      t.text :excerpt, null: false
      t.string :content_digest, null: false

      t.timestamps
    end

    add_index :post_translations, [ :post_id, :locale ], unique: true
  end
end
