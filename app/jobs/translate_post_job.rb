class TranslatePostJob < ApplicationJob
  self.enqueue_after_transaction_commit = true

  queue_as :default

  retry_on PostTranslator::TranslationError, wait: :polynomially_longer, attempts: 5
  discard_on ActiveJob::DeserializationError

  def perform(post_id, source_locale, source_digest)
    post = Post.find(post_id)
    source = post.post_translations.find_by(locale: source_locale)
    return unless source&.content_digest == source_digest

    target_locale = self.class.target_locale(source_locale)

    translated = translator.translate(
      title: source.title,
      body: source.body,
      excerpt: source.excerpt,
      source_locale: source_locale,
      target_locale: target_locale
    )

    PostTranslation.transaction do
      current_source = post.post_translations.lock.find_by(locale: source_locale)
      return unless current_source&.content_digest == source_digest

      target = post.post_translations.find_or_initialize_by(locale: target_locale)
      target.assign_attributes(
        **translated,
        content_digest: PostTranslation.digest_for(**translated)
      )
      target.save!
    end

    PostAudioScheduler.call(post: post, locale: target_locale) if post.published?
  end

  private

  def translator
    PostTranslator.new
  end

  def self.target_locale(source_locale)
    (PostTranslation::SUPPORTED_LOCALES - [ source_locale.to_s ]).first
  end
end
