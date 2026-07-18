require "test_helper"

class PostTranslationSchedulerTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    admin = AdminUser.create!(
      email: "translation-scheduler@example.com",
      password_salt: "salt",
      password_digest: AdminUser.digest_password("password123", "salt")
    )
    category = Category.create!(name: "Scheduler", slug: "scheduler", position: 1)
    @post = Post.create!(
      admin_user: admin,
      category: category,
      title: "Source title",
      slug: "translation-scheduler-post",
      excerpt: "Source excerpt",
      body: "Source body",
      status: :published,
    )
  end

  test "stores the source and enqueues translation for a published post" do
    assert_enqueued_jobs 1, only: TranslatePostJob do
      assert PostTranslationScheduler.call(post: @post, source_locale: :en)
    end

    source = @post.post_translations.find_by!(locale: "en")
    assert_equal @post.title, source.title
    assert_equal PostTranslation.digest_for(title: @post.title, body: @post.body, excerpt: @post.excerpt), source.content_digest
    assert_enqueued_with(job: TranslatePostJob, args: [ @post.id, "en", source.content_digest ])
  end

  test "does not translate drafts or unchanged published content" do
    @post.update!(status: :draft)
    assert_no_enqueued_jobs { assert_not PostTranslationScheduler.call(post: @post, source_locale: :ja) }
    assert_equal @post.title, @post.post_translations.find_by!(locale: "ja").title

    @post.update!(status: :published)
    assert PostTranslationScheduler.call(post: @post, source_locale: :ja)
    clear_enqueued_jobs

    assert_no_enqueued_jobs { assert_not PostTranslationScheduler.call(post: @post, source_locale: :ja) }
  end

  test "invalidates the old target translation when source content changes" do
    PostTranslationScheduler.call(post: @post, source_locale: :en)
    clear_enqueued_jobs
    @post.post_translations.create!(
      locale: "ja",
      title: "古い翻訳",
      body: "古い本文",
      excerpt: "古い要約",
      content_digest: "old"
    )
    @post.update!(title: "Updated source title")

    assert_enqueued_jobs 1, only: TranslatePostJob do
      PostTranslationScheduler.call(post: @post, source_locale: :en)
    end

    assert_not @post.post_translations.exists?(locale: "ja")
    assert_equal "Updated source title", @post.post_translations.find_by!(locale: "en").title
  end
end
