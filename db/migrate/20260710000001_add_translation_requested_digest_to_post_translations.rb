class AddTranslationRequestedDigestToPostTranslations < ActiveRecord::Migration[8.1]
  def change
    add_column :post_translations, :translation_requested_digest, :string
  end
end
