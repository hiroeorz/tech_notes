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

    mp3_data = tts_client.synthesize(text: clean_text, locale: locale)

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

  private

  def tts_client
    @tts_client ||= GoogleTtsClient.new
  end
end
