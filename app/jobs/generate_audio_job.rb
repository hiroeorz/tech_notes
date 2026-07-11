class GenerateAudioJob < ApplicationJob
  self.enqueue_after_transaction_commit = true

  queue_as :default

  retry_on GoogleTtsClient::RequestError, wait: :polynomially_longer, attempts: 5
  discard_on ActiveJob::DeserializationError

  def perform(post_id, locale, content_digest)
    post = Post.find(post_id)
    audio = post.post_audios.find_by(locale: locale)
    return unless audio&.content_digest == content_digest

    audio.update!(status: :generating)

    body = post.localized_content(locale).fetch(:body)
    clean_text = PostAudioCleaner.clean(body)
    return audio.update!(status: :failed, error_message: "No readable text found") if clean_text.blank?

    mp3_data = synthesize_text(clean_text, locale)
    return audio.update!(status: :failed, error_message: "No audio data generated") if mp3_data.blank?

    audio.file.attach(
      io: StringIO.new(mp3_data),
      filename: "post_#{post.id}_#{locale}.mp3",
      content_type: "audio/mpeg"
    )

    audio.update!(status: :completed)
  rescue GoogleTtsClient::RequestError => error
    audio&.update!(status: :failed, error_message: error.message)
    raise
  rescue => error
    audio&.update!(status: :failed, error_message: "#{error.class}: #{error.message}")
    raise
  end

  MAX_CHUNK_CHARS = 250

  private

  def tts_client
    @tts_client ||= GoogleTtsClient.new
  end

  def synthesize_text(text, locale)
    segments = chunk_text(text)
    return nil if segments.blank?

    results = segments.map { |segment| tts_client.synthesize(text: segment, locale: locale) }
    return nil if results.any?(&:nil?)

    results.join
  end

  def chunk_text(text)
    sentences = text.split(/(?<=[。．！？.!?\n])/).map(&:strip).reject(&:blank?)
    return force_split(text) if sentences.blank?

    sentences.flat_map { |s| s.length > MAX_CHUNK_CHARS ? force_split(s) : [ s ] }
  end

  def force_split(text)
    text.scan(/.{1,#{MAX_CHUNK_CHARS}}/m).map(&:strip).reject(&:blank?)
  end
end
