class GenerateHeroImageJob < ApplicationJob
  self.enqueue_after_transaction_commit = true

  queue_as :default

  discard_on ActiveJob::DeserializationError
  discard_on ActiveRecord::RecordNotFound

  def perform(post_id, locale = nil)
    post = Post.includes(:post_translations, images_attachments: :blob).find(post_id)
    return unless post.published?

    locales = locale.present? ? [ locale.to_s ] : PostTranslation::SUPPORTED_LOCALES
    locales.each do |target_locale|
      PostHeroImage.for(post, locale: target_locale)
    end
  end
end
