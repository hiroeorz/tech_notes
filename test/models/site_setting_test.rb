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

  test "localized_profile_title returns english when locale is en and translation exists" do
    setting = SiteSetting.current
    setting.update!(profile_title_en: "Infrastructure Engineer")

    I18n.with_locale(:en) do
      assert_equal "Infrastructure Engineer", setting.localized_profile_title
    end
  end

  test "localized_profile_title falls back to original when locale is en but no translation" do
    setting = SiteSetting.current
    setting.update!(profile_title_en: nil)

    I18n.with_locale(:en) do
      assert_equal setting.profile_title, setting.localized_profile_title
    end
  end

  test "localized_profile_title returns original when locale is ja" do
    setting = SiteSetting.current
    setting.update!(profile_title: "日本語の肩書き")

    I18n.with_locale(:ja) do
      assert_equal "日本語の肩書き", setting.localized_profile_title
    end
  end

  test "localized_profile_bio returns english when locale is en and translation exists" do
    setting = SiteSetting.current
    setting.update!(profile_bio_en: "English bio text")

    I18n.with_locale(:en) do
      assert_equal "English bio text", setting.localized_profile_bio
    end
  end

  test "localized_profile_bio falls back to original when locale is en but no translation" do
    setting = SiteSetting.current
    setting.update!(profile_bio_en: nil)

    I18n.with_locale(:en) do
      assert_equal setting.profile_bio, setting.localized_profile_bio
    end
  end

  test "localized_profile_bio returns original when locale is ja" do
    setting = SiteSetting.current
    setting.update!(profile_bio: "日本語の自己紹介")

    I18n.with_locale(:ja) do
      assert_equal "日本語の自己紹介", setting.localized_profile_bio
    end
  end
end
