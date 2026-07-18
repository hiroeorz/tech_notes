class RemoveKindFromPosts < ActiveRecord::Migration[8.1]
  def up
    execute "UPDATE posts SET kind = 0 WHERE kind = 1"
    remove_index :posts, name: "index_posts_on_status_and_kind_and_published_at"
    remove_column :posts, :kind
    add_index :posts, [ :status, :published_at ], name: "index_posts_on_status_and_published_at"
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "posts.kind cannot be restored after it has been removed"
  end
end
