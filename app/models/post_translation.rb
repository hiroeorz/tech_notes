require "digest"
require "json"

class PostTranslation < ApplicationRecord
  SUPPORTED_LOCALES = %w[en ja].freeze

  belongs_to :post

  validates :locale, inclusion: { in: SUPPORTED_LOCALES }
  validates :locale, uniqueness: { scope: :post_id }
  validates :title, :body, :excerpt, :content_digest, presence: true

  def self.digest_for(title:, body:, excerpt:)
    Digest::SHA256.hexdigest(JSON.generate(title: title.to_s, body: body.to_s, excerpt: excerpt.to_s))
  end
end
