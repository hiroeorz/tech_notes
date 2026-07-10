require "test_helper"

class SiteSettingTest < ActiveSupport::TestCase
  setup { SiteSetting.delete_all }

  test "current creates or returns site setting" do
    setting = SiteSetting.current
    assert setting.persisted?
    assert_equal "Hiroe Tech Notes", setting.blog_title
    assert_equal "https://example.com/github", setting.github_url
    assert_equal "https://example.com/feed.xml", setting.rss_url
  end

  test "validates url format" do
    setting = SiteSetting.current
    setting.site_url = "invalid-url"
    assert_not setting.valid?
    assert_includes setting.errors[:site_url], "must be an http or https URL"
  end
end
