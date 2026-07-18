require "test_helper"

class PostTranslationTest < ActiveSupport::TestCase
  setup do
    admin = AdminUser.create!(
      email: "translation-model@example.com",
      password_salt: "salt",
      password_digest: AdminUser.digest_password("password123", "salt")
    )
    category = Category.create!(name: "Translation", slug: "translation", position: 1)
    @post = Post.create!(
      admin_user: admin,
      category: category,
      title: "Original title",
      slug: "translation-model-post",
      excerpt: "Original excerpt",
      body: "Original body",
      status: :published,
    )
  end

  test "stores one translation per post and locale" do
    translation = @post.post_translations.create!(
      locale: "ja",
      title: "翻訳タイトル",
      excerpt: "翻訳要約",
      body: "翻訳本文",
      content_digest: PostTranslation.digest_for(title: "翻訳タイトル", excerpt: "翻訳要約", body: "翻訳本文")
    )

    duplicate = translation.dup

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:locale], "has already been taken"
  end

  test "localized content uses a translation and falls back to post attributes" do
    @post.post_translations.create!(
      locale: "ja",
      title: "翻訳タイトル",
      excerpt: "翻訳要約",
      body: "翻訳本文",
      content_digest: "digest"
    )

    assert_equal "翻訳タイトル", @post.localized_title(:ja)
    assert_equal "翻訳本文", @post.localized_body(:ja)
    assert_equal "Original title", @post.localized_title(:en)
  end

  test "localized title search uses translations and falls back to the original title" do
    @post.post_translations.create!(
      locale: "ja",
      title: "日本語の検索対象",
      excerpt: "翻訳要約",
      body: "翻訳本文",
      content_digest: "digest"
    )

    assert_includes Post.search_by_title("日本語の検索", locale: :ja), @post
    assert_includes Post.search_by_title("Original", locale: :en), @post
    assert_not_includes Post.search_by_title("Original", locale: :ja), @post
  end

  test "destroying a post destroys its translations" do
    @post.post_translations.create!(
      locale: "ja",
      title: "翻訳タイトル",
      excerpt: "翻訳要約",
      body: "翻訳本文",
      content_digest: "digest"
    )

    assert_difference("PostTranslation.count", -1) { @post.destroy! }
  end
end
