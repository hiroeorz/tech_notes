require "test_helper"

class PostTest < ActiveSupport::TestCase
  setup do
    @admin = AdminUser.create!(
      email: "admin@example.com",
      password_salt: "salt",
      password_digest: AdminUser.digest_password("password123", "salt")
    )
    @category = Category.create!(name: "AWS", slug: "aws", position: 1)
  end

  test "valid post creation and automatic reading minutes calculation" do
    post = Post.new(
      admin_user: @admin,
      category: @category,
      title: "テスト記事",
      slug: "test-post",
      excerpt: "要約です",
      body: "あ" * 1200,
      status: :published,
      kind: :article
    )

    assert post.valid?
    post.save!
    assert_equal 3, post.reading_minutes
    assert_not_nil post.published_at
  end

  test "tag names assignment" do
    post = Post.create!(
      admin_user: @admin,
      category: @category,
      title: "タグテスト",
      slug: "tag-test",
      excerpt: "要約",
      body: "本文",
      status: :published,
      kind: :article
    )
    post.tag_names = "Ruby, Rails, Web"
    post.save!

    assert_equal 3, post.tags.count
    assert_includes post.tag_names, "Ruby"
    assert_includes post.tag_names, "Rails"
  end
end
