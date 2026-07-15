require "test_helper"

class CommentMailerTest < ActionMailer::TestCase
  setup do
    @admin_user = AdminUser.create!(
      email: "admin@example.com",
      password_salt: "salt",
      password_digest: AdminUser.digest_password("password123", "salt")
    )

    @category = Category.create!(name: "Test Cat", name_en: "Test Cat EN", slug: "test-cat", position: 1)

    @post = Post.create!(
      title: "Test Post",
      slug: "test-post",
      excerpt: "Test excerpt",
      body: "Test body",
      category: @category,
      admin_user: @admin_user,
      status: :published,
      published_at: 1.day.ago,
      kind: :article
    )

    @site_setting = SiteSetting.current
    @site_setting.update!(profile_email: "admin@blog.com", blog_title: "Test Blog")

    @comment = @post.comments.create!(
      author_name: "Commenter",
      body: "This is a test comment."
    )
  end

  test "new_comment email is delivered with correct attributes" do
    email = CommentMailer.new_comment(@comment)

    assert_emails 1 do
      email.deliver_now
    end

    assert_equal [ "admin@blog.com" ], email.to
    assert_equal [ ENV.fetch("MAILER_FROM_ADDRESS", "no-reply@aomaro.com") ], email.from
    assert_match "[Test Blog] New comment on \"Test Post\"", email.subject
    assert_match "Commenter", email.body.encoded
    assert_match "This is a test comment.", email.body.encoded
    assert_match "http://example.com/admin/comments", email.body.encoded
    assert_match "http://example.com/en/posts/test-post", email.body.encoded
  end

  test "new_comment email is sent with correct subject in Japanese" do
    @site_setting.update!(blog_title: "テストブログ")

    I18n.with_locale(:ja) do
      email = CommentMailer.new_comment(@comment)
      assert_match "[テストブログ] 記事「Test Post」に新しいコメントが投稿されました", email.subject
      assert_match "http://example.com/ja/posts/test-post", email.html_part.body.decoded
    end
  end
end
