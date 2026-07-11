require "test_helper"

class PostAudioTest < ActiveSupport::TestCase
  setup do
    @admin = AdminUser.create!(
      email: "audio-test@example.com",
      password_salt: "salt",
      password_digest: AdminUser.digest_password("password123", "salt")
    )
    @category = Category.create!(name: "Audio", slug: "audio", position: 1)
    @post = Post.create!(
      admin_user: @admin,
      category: @category,
      title: "Audio Test",
      slug: "audio-test",
      excerpt: "Test excerpt",
      body: "## Hello\nThis is a test article.",
      status: :published,
      kind: :article,
      published_at: Time.current
    )
  end

  test "creates a post audio record" do
    audio = @post.post_audios.create!(
      locale: "ja",
      status: :pending,
      content_digest: "abc123"
    )
    assert audio.persisted?
    assert_equal "ja", audio.locale
    assert_equal "pending", audio.status
  end

  test "validates uniqueness of locale per post" do
    @post.post_audios.create!(locale: "ja", status: :pending, content_digest: "abc")
    duplicate = @post.post_audios.build(locale: "ja", status: :pending, content_digest: "def")
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:locale], "has already been taken"
  end

  test "supports supported locales" do
    assert_includes PostAudio::SUPPORTED_LOCALES, "ja"
    assert_includes PostAudio::SUPPORTED_LOCALES, "en"
  end

  test "digest is deterministic" do
    assert_equal PostAudio.digest_for("hello"), PostAudio.digest_for("hello")
    assert_not_equal PostAudio.digest_for("hello"), PostAudio.digest_for("world")
  end

  test "destroying a post destroys its audio" do
    @post.post_audios.create!(locale: "ja", status: :pending, content_digest: "abc")
    assert_difference -> { PostAudio.count }, -1 do
      @post.destroy
    end
  end
end
