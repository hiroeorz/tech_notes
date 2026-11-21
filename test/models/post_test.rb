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
    )

    assert post.valid?
    post.save!
    assert_equal 3, post.reading_minutes
    assert_not_nil post.published_at
  end

  test "accepts pdf documents" do
    post = create_post

    post.documents.attach(
      io: File.open(Rails.root.join("test/fixtures/files/sample.pdf")),
      filename: "manual.pdf",
      content_type: "application/pdf"
    )

    assert post.valid?
    assert post.documents.attached?
  end

  test "rejects non-pdf documents" do
    post = create_post

    post.documents.attach(
      io: File.open(Rails.root.join("test/fixtures/files/not-image.txt")),
      filename: "notes.txt",
      content_type: "text/plain"
    )

    assert_not post.valid?
    assert_includes post.errors[:documents], I18n.t("activerecord.errors.models.post.attributes.documents.invalid_type")
  end

  test "classifies attachment uploads by content type" do
    image = Struct.new(:content_type, :size).new("image/png", 1.kilobyte)
    document = Struct.new(:content_type, :size).new("application/pdf", 1.kilobyte)
    invalid = Struct.new(:content_type, :size).new("text/plain", 1.kilobyte)

    assert_equal :image, Post.attachment_kind(image)
    assert_equal :document, Post.attachment_kind(document)
    assert_nil Post.attachment_kind(invalid)
  end

  test "rejects pdf documents larger than 20MB" do
    upload = Struct.new(:content_type, :size).new("application/pdf", Post::DOCUMENT_MAX_SIZE + 1)

    assert_not Post.valid_document_upload?(upload)
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
    )
    post.tag_names = "Ruby, Rails, Web"
    post.save!

    assert_equal 3, post.tags.count
    assert_includes post.tag_names, "Ruby"
    assert_includes post.tag_names, "Rails"
  end

  private

  def create_post
    Post.create!(
      admin_user: @admin,
      category: @category,
      title: "添付ファイルテスト",
      slug: "attachment-test",
      excerpt: "要約",
      body: "本文",
      status: :published
    )
  end
end
