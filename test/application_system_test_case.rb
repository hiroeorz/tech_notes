require "test_helper"
require "selenium/webdriver"

Selenium::WebDriver::Chrome::Service.driver_path = "/usr/bin/chromedriver" if File.executable?("/usr/bin/chromedriver")
Selenium::WebDriver::Chrome.path = "/usr/bin/chromium-browser" if File.executable?("/usr/bin/chromium-browser")

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ] do |options|
    options.add_argument("--disable-dev-shm-usage")
    options.add_argument("--no-sandbox")
  end
end
