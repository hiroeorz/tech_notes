class AddLastCommentsReadAtToAdminUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :admin_users, :last_comments_read_at, :datetime
  end
end
