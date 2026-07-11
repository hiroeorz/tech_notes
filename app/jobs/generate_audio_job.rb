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

  MAX_CHUNK_CHARS = 1000

  private

  def tts_client
    @tts_client ||= GoogleTtsClient.new
  end

  def synthesize_text(text, locale)
    segments = chunk_text(text)
    return nil if segments.blank?

    segments.map { |segment| tts_client.synthesize(text: segment, locale: locale) }.join
  end

  def chunk_text(text)
    paragraphs = text.split(/\n\n+/).map(&:strip).reject(&:blank?)
    chunks = []
    current = +""

    paragraphs.each do |para|
      if current.length + para.length + 1 > MAX_CHUNK_CHARS
        chunks << current.strip if current.present?
        if para.length > MAX_CHUNK_CHARS
          chunks.concat(split_text(para))
          current = +""
        else
          current = +para
        end
      else
        current << " " << para
      end
    end
    chunks << current.strip if current.present?
    chunks.presence
  end

  def split_text(text)
    segments = text.split(/(?<=[。．！？.!?\n])/).map(&:strip).reject(&:blank?)
    if segments.blank?
      return text.scan(/.{1,#{MAX_CHUNK_CHARS}}/m).map(&:strip).reject(&:blank?).presence || [ text ]
    end
    result = []
    current = +""
    segments.each do |seg|
      if current.length + seg.length + 1 > MAX_CHUNK_CHARS
        result << current.strip if current.present?
        current = +seg
      else
        current << " " << seg
      end
    end
    result << current.strip if current.present?
    result
  end
end
