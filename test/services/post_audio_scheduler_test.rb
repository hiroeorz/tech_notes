require "test_helper"

class PostAudioSchedulerTest < ActiveJob::TestCase
  setup do
    @admin = AdminUser.create!(
      email: "audio-scheduler@example.com",
      password_salt: "salt",
      password_digest: AdminUser.digest_password("password123", "salt")
    )
    @category = Category.create!(name: "Audio", slug: "audio", position: 1)
    @post = Post.create!(
      admin_user: @admin,
      category: @category,
      title: "Audio Scheduler Test",
      slug: "audio-scheduler-test",
      excerpt: "Test",
      body: "## Hello\nTest body here.",
      status: :published,
      kind: :article,
      published_at: Time.current
    )
  end

  test "schedules audio generation for a published post" do
    assert_enqueued_with(job: GenerateAudioJob) do
      assert PostAudioScheduler.call(post: @post, locale: "ja")
    end
    audio = @post.post_audios.find_by!(locale: "ja")
    assert_equal "pending", audio.status
    assert audio.content_digest.present?
  end

  test "does not schedule for unpublished post" do
    @post.update!(status: :draft)
    assert_no_enqueued_jobs do
      assert_not PostAudioScheduler.call(post: @post, locale: "ja")
    end
  end

  test "does not schedule when generate_audio is false" do
    @post.update!(generate_audio: false)
    assert_no_enqueued_jobs do
      assert_not PostAudioScheduler.call(post: @post, locale: "ja")
    end
  end

  test "does not schedule for unsupported locale" do
    assert_no_enqueued_jobs do
      assert_not PostAudioScheduler.call(post: @post, locale: "fr")
    end
  end

  test "skips scheduling when content has not changed" do
    assert PostAudioScheduler.call(post: @post, locale: "ja")

    assert_no_enqueued_jobs do
      assert_not PostAudioScheduler.call(post: @post, locale: "ja")
    end
  end

  test "reschedules when content has changed" do
    PostAudioScheduler.call(post: @post, locale: "ja")
    @post.update!(body: "## Updated\nNew content here.")

    assert_enqueued_with(job: GenerateAudioJob) do
      assert PostAudioScheduler.call(post: @post, locale: "ja")
    end
  end

  test "schedules for both supported locales" do
    assert_enqueued_jobs(2) do
      PostAudioScheduler.call(post: @post, locale: "ja")
      PostAudioScheduler.call(post: @post, locale: "en")
    end
  end
end
