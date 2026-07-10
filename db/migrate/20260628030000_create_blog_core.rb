class CreateBlogCore < ActiveRecord::Migration[8.1]
  def change
    create_table :categories do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.string :icon_key, null: false, default: "folder"
      t.integer :position, null: false, default: 0

      t.timestamps
    end

    add_index :categories, :slug, unique: true

    create_table :tags do |t|
      t.string :name, null: false
      t.string :slug, null: false

      t.timestamps
    end

    add_index :tags, :slug, unique: true

    create_table :admin_users do |t|
      t.string :email, null: false
      t.string :password_salt, null: false
      t.string :password_digest, null: false

      t.timestamps
    end

    add_index :admin_users, :email, unique: true

    create_table :posts do |t|
      t.references :category, null: false, foreign_key: true
      t.references :admin_user, null: false, foreign_key: true
      t.string :title, null: false
      t.string :slug, null: false
      t.text :excerpt, null: false
      t.text :body, null: false
      t.integer :status, null: false, default: 0
      t.integer :kind, null: false, default: 0
      t.integer :reading_minutes, null: false, default: 1
      t.datetime :published_at

      t.timestamps
    end

    add_index :posts, :slug, unique: true
    add_index :posts, [ :status, :kind, :published_at ]

    create_table :post_tags do |t|
      t.references :post, null: false, foreign_key: true
      t.references :tag, null: false, foreign_key: true

      t.timestamps
    end

    add_index :post_tags, [ :post_id, :tag_id ], unique: true

    create_table :site_settings do |t|
      t.string :blog_title, null: false, default: "Hiroe Tech Notes"
      t.string :tagline, null: false, default: "あるエンジニアの技術ノート"
      t.string :site_url, null: false, default: "https://example.com"
      t.text :description, null: false
      t.string :ogp_image_path
      t.string :profile_name, null: false, default: "Hiroe"
      t.string :profile_title, null: false, default: "インフラエンジニア / プログラマ"
      t.string :profile_email, null: false, default: "hiroe@example.com"
      t.text :profile_bio, null: false
      t.string :profile_image_path
      t.string :github_url
      t.string :x_url
      t.string :rss_url
      t.string :zenn_url
      t.string :note_url
      t.boolean :profile_visible, null: false, default: true
      t.boolean :sns_visible, null: false, default: true
      t.string :default_theme, null: false, default: "light"
      t.integer :posts_per_page, null: false, default: 10

      t.timestamps
    end
  end
end
