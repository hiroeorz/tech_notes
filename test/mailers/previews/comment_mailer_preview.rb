class CommentMailerPreview < ActionMailer::Preview
  def new_comment
    comment = Comment.new(
      author_name: "Test User",
      body: "This is a test comment body.\n\nWith multiple paragraphs.",
      created_at: Time.current,
      post: Post.publicly_visible.first
    )
    CommentMailer.new_comment(comment)
  end
end
