require "test_helper"

class GenerateAudioJobTest < ActiveJob::TestCase
  setup do
    @admin = AdminUser.create!(
      email: "generate-audio@example.com",
      password_salt: "salt",
      password_digest: AdminUser.digest_password("password123", "salt")
    )
    @category = Category.create!(name: "Audio", slug: "audio", position: 1)
    @post = Post.create!(
      admin_user: @admin,
      category: @category,
      title: "Generate Audio Test",
      slug: "generate-audio-test",
      excerpt: "Test",
      body: "## Hello\nTest body.",
      status: :published,
      published_at: Time.current
    )
    @digest = PostAudio.digest_for(@post.body)
    @audio = @post.post_audios.create!(
      locale: "ja",
      status: :pending,
      content_digest: @digest,
      voice: "ja-JP-Neural2-C"
    )
  end

  test "aborts when content digest does not match" do
    GenerateAudioJob.perform_now(@post.id, "ja", "wrong-digest")
    @audio.reload
    assert_equal "pending", @audio.status
    assert_not @audio.file.attached?
  end

  test "aborts when audio record is missing" do
    assert_nil GenerateAudioJob.perform_now(@post.id, "en", "some-digest")
  end

  test "marks as failed when no readable text" do
    @post.update!(body: "```code only```")
    new_digest = PostAudio.digest_for("```code only```")
    @audio.update!(content_digest: new_digest)

    GenerateAudioJob.perform_now(@post.id, "ja", new_digest)
    @audio.reload
    assert_equal "failed", @audio.status
    assert_equal "No readable text found", @audio.error_message
  end

  test "handles missing post gracefully" do
    assert_raises(ActiveRecord::RecordNotFound) do
      GenerateAudioJob.perform_now(999999, "ja", "digest")
    end
  end
end
