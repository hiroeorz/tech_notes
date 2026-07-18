require "test_helper"

class TranslatePostJobTest < ActiveJob::TestCase
  class FakeTranslator
    attr_reader :arguments

    def translate(**arguments)
      @arguments = arguments
      { title: "翻訳タイトル", body: "## 翻訳本文", excerpt: "翻訳要約" }
    end
  end

  class ExplodingTranslator
    def translate(**)
      raise "stale jobs must not call the translator"
    end
  end

  setup do
    admin = AdminUser.create!(
      email: "translation-job@example.com",
      password_salt: "salt",
      password_digest: AdminUser.digest_password("password123", "salt")
    )
    category = Category.create!(name: "Job", slug: "job", position: 1)
    @post = Post.create!(
      admin_user: admin,
      category: category,
      title: "Source title",
      slug: "translation-job-post",
      excerpt: "Source excerpt",
      body: "Source body",
      status: :published,
    )
    @digest = PostTranslation.digest_for(title: @post.title, body: @post.body, excerpt: @post.excerpt)
    @post.post_translations.create!(
      locale: "en",
      title: @post.title,
      body: @post.body,
      excerpt: @post.excerpt,
      content_digest: @digest
    )
  end

  test "stores the translated content in the target locale" do
    translator = FakeTranslator.new
    job = TranslatePostJob.new
    job.define_singleton_method(:translator) { translator }

    job.perform(@post.id, "en", @digest)

    translation = @post.post_translations.find_by!(locale: "ja")
    assert_equal "翻訳タイトル", translation.title
    assert_equal "## 翻訳本文", translation.body
    assert_equal "翻訳要約", translation.excerpt
    assert_equal "en", translator.arguments.fetch(:source_locale)
    assert_equal "ja", translator.arguments.fetch(:target_locale)
  end

  test "discards stale work before and after the ai call" do
    @post.post_translations.find_by!(locale: "en").update!(content_digest: "new-digest")
    job = TranslatePostJob.new
    translator = ExplodingTranslator.new
    job.define_singleton_method(:translator) { translator }

    job.perform(@post.id, "en", @digest)

    assert_not @post.post_translations.exists?(locale: "ja")
  end
end
