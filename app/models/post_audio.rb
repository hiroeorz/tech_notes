class PostAudio < ApplicationRecord
  AUDIO_STORAGE_SERVICE = Rails.env.production? ? :cloudflare_r2_audio : :local

  belongs_to :post
  has_one_attached :file, service: AUDIO_STORAGE_SERVICE

  validates :locale, presence: true
  validates :locale, uniqueness: { scope: :post_id }
  validates :status, presence: true

  enum :status, { pending: 0, generating: 1, completed: 2, failed: 3 }

  SUPPORTED_LOCALES = %w[ja en].freeze

  def self.digest_for(text)
    Digest::SHA256.hexdigest(text.to_s)
  end
end
