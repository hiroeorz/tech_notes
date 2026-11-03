# typed: true

require "uri"

class PostHeroImage
  WIDTH = 1200
  HEIGHT = 630
  VARIANT_VERSION = 1
  VARIANT_TRANSFORMATIONS = {
    resize_to_fill: [ WIDTH, HEIGHT ],
    format: :jpeg,
    saver: { quality: 85, background: [ 255, 255, 255 ] }
  }.freeze

  def self.for(post, locale: I18n.locale, base_url: nil)
    new(post, locale: locale, base_url: base_url).call
  end

  def initialize(post, locale:, base_url:)
    @post = post
    @locale = locale.to_s
    @base_url = base_url.to_s.presence
  end

  def call
    image = MarkdownRenderer.new(post.localized_body(locale)).first_image
    return if image.blank?

    source_url = absolute_url(image[:src])
    return if source_url.blank?

    attachment = matching_attachment(source_url)
    if attachment
      variant_url = cached_variant_url(attachment)
      return if variant_url.blank?

      return {
        url: variant_url,
        alt: alt_text(image),
        width: WIDTH,
        height: HEIGHT
      }
    end

    return if missing_cdn_blob?(source_url)

    {
      url: source_url,
      alt: alt_text(image)
    }
  end

  private

  attr_reader :post, :locale, :base_url

  def alt_text(image)
    image[:alt].to_s.squish.presence || post.localized_title(locale)
  end

  def absolute_url(value)
    url = value.to_s.strip
    return if url.blank?

    candidate = if url.start_with?("//")
      "#{URI.parse(base_url).scheme}:#{url}" if base_url.present?
    elsif url.start_with?("/")
      "#{base_url}#{url}" if base_url.present?
    else
      url
    end
    return if candidate.blank?

    uri = URI.parse(candidate)
    return if uri.userinfo.present?
    return unless uri.is_a?(URI::HTTP) && uri.host.present? && uri.scheme.to_s.downcase.in?(%w[http https])

    candidate
  rescue URI::Error
    nil
  end

  def matching_attachment(url)
    return unless ActiveStoragePublicUrl.configured?

    post.images.attachments.detect do |attachment|
      public_storage_attachment?(attachment) &&
        comparable_url(ActiveStoragePublicUrl.for(attachment)) == comparable_url(url)
    end
  rescue ArgumentError
    nil
  end

  def public_storage_attachment?(attachment)
    ActiveStoragePublicUrl.current_service?(attachment)
  end

  def comparable_url(value)
    uri = URI.parse(value.to_s)
    uri.query = nil
    uri.fragment = nil
    uri.to_s
  rescue URI::Error
    value.to_s
  end

  def cached_variant_url(attachment)
    return unless ActiveStoragePublicUrl.configured?
    return if Rails.cache.read(failure_cache_key(attachment))

    Rails.cache.fetch(cache_key(attachment), expires_in: 30.days, skip_nil: true) do
      variant = attachment.variant(VARIANT_TRANSFORMATIONS).processed
      ActiveStoragePublicUrl.for_key(variant.key)
    end
  rescue StandardError => error
    mark_variant_failure(attachment)
    Rails.logger.warn("PostHeroImage variant generation failed for post #{post.id}: #{error.class}")
    nil
  end

  def mark_variant_failure(attachment)
    Rails.cache.write(failure_cache_key(attachment), true, expires_in: 5.minutes)
  rescue StandardError
    nil
  end

  def missing_cdn_blob?(url)
    key = cdn_key(url)
    return false if key.blank?

    blob = ActiveStorage::Blob.find_by(key: key)
    blob.blank? || !ActiveStoragePublicUrl.current_service?(blob)
  end

  def cdn_key(url)
    cdn_base_url = ActiveStoragePublicUrl.configured_base_url
    return if cdn_base_url.blank?

    normalized = comparable_url(url)
    return unless normalized.start_with?("#{cdn_base_url}/")

    normalized.delete_prefix("#{cdn_base_url}/")
  end

  def cache_key(attachment)
    [
      "post_hero_image",
      VARIANT_VERSION,
      post.cache_key_with_version,
      locale,
      attachment.blob.key,
      ActiveStoragePublicUrl.configured_base_url
    ]
  end

  def failure_cache_key(attachment)
    [ cache_key(attachment), "failure" ]
  end
end
