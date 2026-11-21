require "application_system_test_case"

class AdminPostAttachmentUploadTest < ApplicationSystemTestCase
  setup do
    @previous_public_base_url = ENV["ACTIVE_STORAGE_PUBLIC_BASE_URL"]
    ENV["ACTIVE_STORAGE_PUBLIC_BASE_URL"] = "https://cdn.example.com"

    admin = AdminUser.create!(
      email: "admin@example.com",
      password_salt: "salt",
      password_digest: AdminUser.digest_password("password123", "salt")
    )
    category = Category.create!(name: "AWS", slug: "aws", icon_key: "aws", position: 1)
    @post = Post.create!(
      admin_user: admin,
      category: category,
      title: "添付ファイルのテスト",
      slug: "attachment-upload-test",
      excerpt: "添付ファイルのテストです。",
      body: "本文です。",
      status: :draft
    )

    sign_in_as_admin
  end

  teardown do
    ENV["ACTIVE_STORAGE_PUBLIC_BASE_URL"] = @previous_public_base_url
  end

  test "admin uploads a pdf and an image from the shared attachment input" do
    visit edit_admin_post_path(@post.slug)

    find("input[data-post-attachment-input]:not([disabled])").set(Rails.root.join("test/fixtures/files/sample.pdf"))
    assert_text I18n.t("js.editor.upload_success")
    assert_includes find("textarea[name='post[body]']").value, "[sample.pdf](https://cdn.example.com/"

    find("input[data-post-attachment-input]:not([disabled])").set(Rails.root.join("test/fixtures/files/hero.png"))
    assert_text I18n.t("js.editor.upload_success")
    assert_includes find("textarea[name='post[body]']").value, "![hero](https://cdn.example.com/"
  end
end
