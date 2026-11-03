require "test_helper"
require "vips"

class PostHeroImageTest < ActiveSupport::TestCase
  setup do
    @previous_public_storage_url = ENV["ACTIVE_STORAGE_PUBLIC_BASE_URL"]
    ENV["ACTIVE_STORAGE_PUBLIC_BASE_URL"] = "https://cdn.example.com"

    @admin = AdminUser.create!(
      email: "hero-image@example.com",
      password_salt: "salt",
      password_digest: AdminUser.digest_password("password123", "salt")
    )
    @category = Category.create!(name: "Hero", slug: "hero", position: 1)
    @post = Post.create!(
      admin_user: @admin,
      category: @category,
      title: "OGP画像のテスト",
      slug: "hero-image-test",
      excerpt: "OGP画像のテストです。",
      body: "本文",
      status: :published,
      published_at: Time.current
    )
    @post.images.attach(
      io: File.open(Rails.root.join("test/fixtures/files/hero.png")),
      filename: "hero.png",
      content_type: "image/png"
    )
    @attachment = @post.images.attachments.last
    @post.update!(body: "![ヒーロー](#{ActiveStoragePublicUrl.for(@attachment)})")
    @post.reload
  end

  teardown do
    ENV["ACTIVE_STORAGE_PUBLIC_BASE_URL"] = @previous_public_storage_url
  end

  test "uses a 1200x630 variant of the first attached image" do
    image = PostHeroImage.for(@post, locale: :en, base_url: "https://blog.example.com")
    variant = @attachment.variant(PostHeroImage::VARIANT_TRANSFORMATIONS).processed

    assert_equal "ヒーロー", image[:alt]
    assert_equal PostHeroImage::WIDTH, image[:width]
    assert_equal PostHeroImage::HEIGHT, image[:height]
    assert_equal ActiveStoragePublicUrl.for_key(variant.key), image[:url]

    processed_image = Vips::Image.new_from_buffer(variant.download, "")
    assert_equal PostHeroImage::WIDTH, processed_image.width
    assert_equal PostHeroImage::HEIGHT, processed_image.height
  end

  test "uses an external image as-is" do
    @post.update!(body: "![external](https://images.example.com/hero.png)")

    image = PostHeroImage.for(@post, locale: :en, base_url: "https://blog.example.com")

    assert_equal "https://images.example.com/hero.png", image[:url]
    assert_nil image[:width]
    assert_nil image[:height]
  end

  test "resolves a site-relative image against the request base URL" do
    @post.update!(body: "![relative](/images/hero.png)")

    image = PostHeroImage.for(@post, locale: :en, base_url: "https://blog.example.com")

    assert_equal "https://blog.example.com/images/hero.png", image[:url]
  end

  test "falls back to the article title when the image has no alt" do
    @post.update!(body: "![](https://images.example.com/hero.png)")

    image = PostHeroImage.for(@post, locale: :en, base_url: "https://blog.example.com")

    assert_equal "OGP画像のテスト", image[:alt]
  end

  test "ignores unsafe or malformed image URLs" do
    [
      "javascript:alert(1)",
      "http://",
      "https:///missing-host.png",
      "///cdn.example.com/image.png",
      "//user:pass@example.com/image.png",
      "data:image/png;base64,AAAA",
      "file:///tmp/image.png"
    ].each do |url|
      @post.update!(body: "![unsafe](#{url})")

      assert_nil PostHeroImage.for(@post, locale: :en, base_url: "https://blog.example.com"), "expected #{url.inspect} to be ignored"
    end
  end

  test "returns nil when the image variant cannot be generated" do
    broken_post = Post.create!(
      admin_user: @admin,
      category: @category,
      title: "壊れた画像のテスト",
      slug: "broken-hero-image-test",
      excerpt: "壊れた画像のテストです。",
      body: "本文",
      status: :published,
      published_at: Time.current
    )
    broken_post.images.attach(
      io: File.open(Rails.root.join("test/fixtures/files/not-image.txt")),
      filename: "broken.png",
      content_type: "image/png"
    )
    attachment = broken_post.images.attachments.last
    broken_post.update!(body: "![壊れた画像](#{ActiveStoragePublicUrl.for(attachment)})")
    broken_post.reload

    assert_nil PostHeroImage.for(broken_post, locale: :en, base_url: "https://blog.example.com")
  end

  test "returns nil when the CDN image no longer has a blob" do
    @attachment.purge
    @post.reload

    assert_nil PostHeroImage.for(@post, locale: :en, base_url: "https://blog.example.com")
  end

  test "returns nil when the article has no image" do
    @post.update!(body: "本文だけです。")

    assert_nil PostHeroImage.for(@post, locale: :en, base_url: "https://blog.example.com")
  end
end
