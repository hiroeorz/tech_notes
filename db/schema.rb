# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_07_05_163437) do
  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "admin_users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "password_digest", null: false
    t.string "password_salt", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_admin_users_on_email", unique: true
  end

  create_table "categories", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "icon_key", default: "folder", null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_categories_on_slug", unique: true
  end

  create_table "comments", force: :cascade do |t|
    t.string "author_name", limit: 30, null: false
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.integer "post_id", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_comments_on_created_at"
    t.index ["ip_address"], name: "index_comments_on_ip_address"
    t.index ["post_id"], name: "index_comments_on_post_id"
  end

  create_table "post_tags", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "post_id", null: false
    t.integer "tag_id", null: false
    t.datetime "updated_at", null: false
    t.index ["post_id", "tag_id"], name: "index_post_tags_on_post_id_and_tag_id", unique: true
    t.index ["post_id"], name: "index_post_tags_on_post_id"
    t.index ["tag_id"], name: "index_post_tags_on_tag_id"
  end

  create_table "posts", force: :cascade do |t|
    t.integer "admin_user_id", null: false
    t.text "body", null: false
    t.integer "category_id", null: false
    t.datetime "created_at", null: false
    t.text "excerpt", null: false
    t.integer "kind", default: 0, null: false
    t.datetime "published_at"
    t.integer "reading_minutes", default: 1, null: false
    t.string "slug", null: false
    t.integer "status", default: 0, null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["admin_user_id"], name: "index_posts_on_admin_user_id"
    t.index ["category_id"], name: "index_posts_on_category_id"
    t.index ["slug"], name: "index_posts_on_slug", unique: true
    t.index ["status", "kind", "published_at"], name: "index_posts_on_status_and_kind_and_published_at"
  end

  create_table "site_settings", force: :cascade do |t|
    t.string "blog_title", default: "Hiroe Tech Notes", null: false
    t.datetime "created_at", null: false
    t.string "default_theme", default: "light", null: false
    t.text "description", null: false
    t.string "github_url"
    t.string "note_url"
    t.string "ogp_image_path"
    t.integer "posts_per_page", default: 10, null: false
    t.text "profile_bio", null: false
    t.string "profile_email", default: "hiroe@example.com", null: false
    t.string "profile_image_path"
    t.string "profile_name", default: "Hiroe", null: false
    t.string "profile_title", default: "インフラエンジニア / プログラマ", null: false
    t.boolean "profile_visible", default: true, null: false
    t.string "rss_url"
    t.string "site_url", default: "https://hiroe-tech-notes.dev", null: false
    t.boolean "sns_visible", default: true, null: false
    t.string "tagline", default: "技術を、実践し、言語化する。", null: false
    t.datetime "updated_at", null: false
    t.string "x_url"
    t.string "zenn_url"
  end

  create_table "tags", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_tags_on_slug", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "comments", "posts"
  add_foreign_key "post_tags", "posts"
  add_foreign_key "post_tags", "tags"
  add_foreign_key "posts", "admin_users"
  add_foreign_key "posts", "categories"
end
