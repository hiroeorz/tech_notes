class PostTranslationScheduler
  def self.call(post:, source_locale:)
    new(post:, source_locale:).call
  end

  def initialize(post:, source_locale:)
    @post = post
    @source_locale = source_locale.to_s
  end

  def call
    validate_locale!
    content = { title: post[:title], body: post[:body], excerpt: post[:excerpt] }
    digest = PostTranslation.digest_for(**content)
    source_translation = post.post_translations.find_or_initialize_by(locale: source_locale)
    source_changed = !source_translation.persisted? || source_translation.content_digest != digest

    if source_changed
      source_translation.assign_attributes(
        **content,
        content_digest: digest,
        translation_requested_digest: nil
      )
      source_translation.save!
      post.post_translations.where(locale: target_locale).delete_all
    end

    return false unless post.published?
    return false if source_translation.translation_requested_digest == digest

    source_translation.update!(translation_requested_digest: digest)
    TranslatePostJob.perform_later(post.id, source_locale, digest)
    true
  end

  private

  attr_reader :post, :source_locale

  def validate_locale!
    return if source_locale.in?(PostTranslation::SUPPORTED_LOCALES)

    raise ArgumentError, "Unsupported source locale: #{source_locale}"
  end

  def target_locale
    (PostTranslation::SUPPORTED_LOCALES - [ source_locale ]).first
  end
end
