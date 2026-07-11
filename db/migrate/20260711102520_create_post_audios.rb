class CreatePostAudios < ActiveRecord::Migration[8.1]
  def change
    create_table :post_audios do |t|
      t.references :post, null: false, foreign_key: true
      t.string :locale, null: false
      t.integer :status, null: false, default: 0
      t.string :content_digest
      t.string :voice
      t.text :error_message

      t.timestamps
    end

    add_index :post_audios, [ :post_id, :locale ], unique: true
  end
end
