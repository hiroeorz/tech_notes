# typed: true

require "uri"

class SiteSetting < ApplicationRecord
  has_one_attached :ogp_image
  has_one_attached :profile_image

  validates :blog_title, :tagline, :site_url, :description, :profile_name, :profile_title, :profile_bio, presence: true
  validates :profile_email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :default_theme, inclusion: { in: %w[light dark] }
  validates :posts_per_page, numericality: { only_integer: true, greater_than_or_equal_to: 5, less_than_or_equal_to: 50 }
  validate :validate_site_url
  validate :validate_ogp_image
  validate :validate_profile_image
  validate :validate_external_urls

  def self.current
    first_or_create!(
      description: "インフラ、クラウド、SRE、自動化などに関する学びや実践を記録する個人のテックブログです。",
      profile_bio: "クラウドや自動化が好きで、日々の業務や個人の実験で得た学びを発信しています。",
      github_url: "https://example.com/github",
      x_url: "https://example.com/x",
      rss_url: "https://example.com/feed.xml",
      zenn_url: "https://example.com/zenn",
      note_url: "https://example.com/note"
    )
  end

  def localized_profile_title(locale = I18n.locale)
    return profile_title_en if locale.to_s == "en" && profile_title_en.present?
    profile_title
  end

  def localized_profile_bio(locale = I18n.locale)
    return profile_bio_en if locale.to_s == "en" && profile_bio_en.present?
    profile_bio
  end

  private

  def validate_ogp_image
    validate_image_attachment(ogp_image, label: "OGP画像", max_size: 2.megabytes)
  end

  def validate_profile_image
    validate_image_attachment(profile_image, label: "プロフィール画像", max_size: 1.megabyte)
  end

  def validate_site_url
    return if valid_http_url?(site_url)

    errors.add(:site_url, :format)
  end

  def validate_external_urls
    %i[github_url x_url rss_url zenn_url note_url].each do |attribute|
      value = public_send(attribute)
      next if value.blank? || valid_http_url?(value)

      errors.add(attribute, :format)
    end
  end

  def valid_http_url?(value)
    uri = URI.parse(value.to_s)
    uri.is_a?(URI::HTTP) && uri.host.present? && uri.scheme.in?(%w[http https])
  rescue URI::InvalidURIError
    false
  end

  def validate_image_attachment(attachment, label:, max_size:)
    return unless attachment.attached?

    unless attachment.blob.content_type.in?(%w[image/jpeg image/png])
      errors.add(attachment.name, :invalid_type, label: label)
    end

    return unless attachment.blob.byte_size > max_size

    errors.add(attachment.name, :too_large, label: label, max_size: max_size / 1.megabyte)
  end
end
