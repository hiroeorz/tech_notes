require "test_helper"

class GenerateHeroImageJobTest < ActiveJob::TestCase
  setup do
    @previous_public_storage_url = ENV["ACTIVE_STORAGE_PUBLIC_BASE_URL"]
    ENV["ACTIVE_STORAGE_PUBLIC_BASE_URL"] = "https://cdn.example.com"

    admin = AdminUser.create!(
      email: "hero-image-job@example.com",
      password_salt: "salt",
      password_digest: AdminUser.digest_password("password123", "salt")
    )
    category = Category.create!(name: "Hero Job", slug: "hero-job", position: 1)
    @post = Post.create!(
      admin_user: admin,
      category: category,
      title: "OGP画像ジョブのテスト",
      slug: "hero-image-job-test",
      excerpt: "OGP画像ジョブのテストです。",
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

  test "pre-generates the OGP variant for published posts" do
    assert_difference -> { ActiveStorage::VariantRecord.count }, 1 do
      GenerateHeroImageJob.perform_now(@post.id)
    end
  end

  test "does not generate variants for unpublished posts" do
    @post.update!(status: :draft)

    assert_no_difference -> { ActiveStorage::VariantRecord.count } do
      GenerateHeroImageJob.perform_now(@post.id)
    end
  end

  test "discards jobs for deleted posts" do
    assert_nothing_raised do
      GenerateHeroImageJob.perform_now(999_999)
    end
  end
end
