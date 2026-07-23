require "application_system_test_case"

class PublishModalLayoutTest < ApplicationSystemTestCase
  setup do
    AdminUser.create!(
      email: "admin@example.com",
      password_salt: "salt",
      password_digest: AdminUser.digest_password("password123", "salt")
    )
    Category.create!(name: "AWS", slug: "aws", icon_key: "aws", position: 1)

    visit admin_login_path
    fill_in "Email", with: "admin@example.com"
    fill_in "Password", with: "password123"
    click_on "Log in"
    assert_current_path admin_posts_path
  end

  test "admin can open publish modal on new post page" do
    visit new_admin_post_path
    open_modal

    assert_selector ".publish-modal-card[role='dialog']"
    assert_selector "#modal-title", text: "Publish Settings"
  end

  test "desktop layout uses two columns without unnecessary body scroll" do
    resize_viewport_to(1280, 720)
    visit new_admin_post_path
    open_modal

    assert_equal 2, modal_column_count
    assert_not modal_body_scrolls?
  end

  test "mobile layout uses one column and keeps actions in the viewport" do
    resize_viewport_to(375, 812)
    visit new_admin_post_path
    open_modal

    assert_equal 1, modal_column_count
    assert_equal 2, evaluate_script("getComputedStyle(document.querySelector('.modal-footer')).gridTemplateColumns.split(/\\s+/).length")
    assert modal_body_scrolls?
    assert_equal "auto", evaluate_script("getComputedStyle(document.querySelector('.modal-body')).overflowY")
    assert evaluate_script("document.querySelector('.publish-modal-card').getBoundingClientRect().bottom <= window.innerHeight + 1")
    assert evaluate_script("document.querySelector('.modal-footer').getBoundingClientRect().bottom <= window.innerHeight + 1")
  end

  test "wide low viewport keeps the modal and actions visible" do
    resize_viewport_to(900, 500)
    visit new_admin_post_path
    open_modal

    assert_equal 2, modal_column_count
    assert evaluate_script("document.querySelector('.publish-modal-card').getBoundingClientRect().bottom <= window.innerHeight + 1")
    assert evaluate_script("document.querySelector('.modal-footer').getBoundingClientRect().bottom <= window.innerHeight + 1")
  end

  test "AI buttons are outside explicit slug and excerpt labels" do
    resize_viewport_to(1280, 720)
    visit new_admin_post_path
    open_modal

    assert_selector "label[for='post_slug']", text: /Slug/
    assert_selector "label[for='post_excerpt']", text: /Excerpt/
    assert_no_selector ".publish-modal-card label .ai-icon-button"

    find("label[for='post_slug']").click
    assert_selector "#post_slug:focus"
    assert_selector "[data-post-summary-target='slugMessage'][hidden]", visible: :all

    find("label[for='post_excerpt']").click
    assert_selector "#post_excerpt:focus"
    assert_selector "[data-post-summary-target='message'][hidden]", visible: :all
  end

  private

  def resize_viewport_to(width, height)
    page.driver.browser.manage.window.resize_to(width, height)
    chrome_height = evaluate_script("window.outerHeight - window.innerHeight")
    page.driver.browser.manage.window.resize_to(width, height + chrome_height) if chrome_height.positive?
  end

  def open_modal
    find("[data-open-publish-modal]").click
    assert_selector "[data-publish-modal-backdrop]:not([hidden])", visible: :visible
  end

  def modal_column_count
    evaluate_script("getComputedStyle(document.querySelector('.publish-modal-grid')).gridTemplateColumns.split(/\\s+/).length")
  end

  def modal_body_scrolls?
    evaluate_script("document.querySelector('.modal-body').scrollHeight > document.querySelector('.modal-body').clientHeight + 1")
  end
end
