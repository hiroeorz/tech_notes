class PostAudioScheduler
  def self.call(post:, locale:)
    new(post:, locale:).call
  end

  def initialize(post:, locale:)
    @post = post
    @locale = locale.to_s
  end

  def call
    return false unless post.published?
    return false unless post.generate_audio?
    return false unless locale.in?(PostAudio::SUPPORTED_LOCALES)

    content = post.localized_content(locale).fetch(:body)
    digest = PostAudio.digest_for(content)
    audio = post.post_audios.find_or_initialize_by(locale: locale)

    return false if audio.completed? && audio.content_digest == digest

    audio.assign_attributes(
      content_digest: digest,
      voice: GoogleTtsClient::VOICE_MAP.dig(locale, :name),
      status: :pending,
      error_message: nil
    )
    audio.save!

    GenerateAudioJob.perform_later(post.id, locale, digest)
    true
  end

  private

  attr_reader :post, :locale
end
