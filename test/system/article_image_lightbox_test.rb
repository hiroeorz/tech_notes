require "application_system_test_case"

class ArticleImageLightboxTest < ApplicationSystemTestCase
  setup do
    admin = AdminUser.create!(
      email: "admin@example.com",
      password_salt: "salt",
      password_digest: AdminUser.digest_password("password123", "salt")
    )
    category = Category.create!(name: "AWS", slug: "aws", icon_key: "aws", position: 1)
    @post = Post.create!(
      admin_user: admin,
      category: category,
      title: "画像を含む記事",
      slug: "post-with-image",
      excerpt: "画像拡大の確認用記事です。",
      body: "## 構成例\n\n![構成図](/icon.png)",
      status: :published,
      kind: :article,
      published_at: Time.current
    )
  end

  test "visitor can open and close a markdown image lightbox" do
    visit post_path(slug: @post.slug)

    image = find(".article-image img")
    image.click
    assert_selector ".image-lightbox[role='dialog'][aria-modal='true']"
    assert_selector ".image-lightbox-image[src$='/icon.png'][alt='構成図']"

    find(".image-lightbox-close").click
    assert_no_selector ".image-lightbox"

    image.send_keys :enter
    assert_selector ".image-lightbox"
    execute_script("document.querySelector('.image-lightbox').click()")
    assert_no_selector ".image-lightbox"

    image.click
    assert_selector ".image-lightbox"
    send_keys :escape
    assert_no_selector ".image-lightbox"
  end
end
