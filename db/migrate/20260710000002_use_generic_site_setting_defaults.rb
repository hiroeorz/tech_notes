class UseGenericSiteSettingDefaults < ActiveRecord::Migration[8.1]
  def up
    change_column_default :site_settings, :site_url, "https://example.com"
    change_column_default :site_settings, :profile_email, "admin@example.com"
  end

  def down
    change_column_default :site_settings, :site_url, nil
    change_column_default :site_settings, :profile_email, nil
  end
end
