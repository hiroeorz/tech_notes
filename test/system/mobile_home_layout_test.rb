require "application_system_test_case"

class MobileHomeLayoutTest < ApplicationSystemTestCase
  setup do
    admin = AdminUser.create!(
      email: "admin@example.com",
      password_salt: "salt",
      password_digest: AdminUser.digest_password("password123", "salt")
    )
    category = Category.create!(name: "AWS", slug: "aws", icon_key: "aws", position: 1)
    post = Post.create!(
      admin_user: admin,
      category: category,
      title: "OpenCodeのスキルを使ってRuby 4.0.5にアップグレード完了",
      slug: "ruby-upgrade-with-opencode-skills",
      excerpt: "モバイル幅のトップページで長い実験ログカードが収まることを確認するための本文です。",
      body: <<~MARKDOWN,
        ```terraform
        resource "aws_s3_bucket" "example" {
          bucket = "sample-tech-notes"
          acl    = "private"
          tags = {
            Name = "sample-tech-notes-bucket"
          }
        }
        ```
      MARKDOWN
      status: :published,
      published_at: Time.current
    )
    post.tags << Tag.create!(name: "Terraform", slug: "terraform")
  end

  test "top page fits within mobile viewport" do
    resize_to_mobile

    visit root_path

    assert_selector ".daily-card"
    assert_selector ".experiments-section h2", text: /Latest Posts|最新/

    viewport_width = page.evaluate_script("document.documentElement.clientWidth")
    page_width = page.evaluate_script("document.documentElement.scrollWidth")
    daily_card_width = page.evaluate_script("document.querySelector('.daily-card').getBoundingClientRect().width")
    latest_card_width = page.evaluate_script("document.querySelector('.experiment-card').getBoundingClientRect().width")

    assert_operator page_width, :<=, viewport_width
    assert_operator daily_card_width, :<=, viewport_width
    assert_operator latest_card_width, :<=, viewport_width
  end

  private

  def resize_to_mobile
    page.driver.browser.manage.window.resize_to(390, 844)
  end
end
