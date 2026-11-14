require "test_helper"
require "selenium/webdriver"

Selenium::WebDriver::Chrome::Service.driver_path = "/usr/bin/chromedriver" if File.executable?("/usr/bin/chromedriver")
Selenium::WebDriver::Chrome.path = "/usr/bin/chromium-browser" if File.executable?("/usr/bin/chromium-browser")

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ] do |options|
    options.add_argument("--disable-dev-shm-usage")
    options.add_argument("--no-sandbox")
  end

  # ログインフォームの送信ボタンは Turnstile のコールバックまで無効化されるため、
  # 有効になるまで待ってからクリックする（外部スクリプトの読み込みタイミングによる flaky を防ぐ）。
  def sign_in_as_admin(email: "admin@example.com", password: "password123")
    visit admin_login_path
    fill_in "Email", with: email
    fill_in "Password", with: password
    find_button("Log in", disabled: false).click
    assert_current_path admin_posts_path
  end
end
