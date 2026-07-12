class AddProfileTranslationToSiteSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :site_settings, :profile_title_en, :string
    add_column :site_settings, :profile_bio_en, :text
  end
end
