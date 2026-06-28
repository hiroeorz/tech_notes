require "test_helper"

class SiteSettingTest < ActiveSupport::TestCase
  test "current creates or returns site setting" do
    setting = SiteSetting.current
    assert setting.persisted?
    assert_equal "Hiroe Tech Notes", setting.blog_title
  end

  test "validates url format" do
    setting = SiteSetting.current
    setting.site_url = "invalid-url"
    assert_not setting.valid?
    assert_includes setting.errors[:site_url], "はhttpまたはhttpsのURLを入力してください"
  end
end
