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

  MAX_CHUNK_BYTES = 3500
  MAX_SENTENCE_CHARS = 1500

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
      if para.bytesize >= MAX_CHUNK_BYTES
        chunks << current.strip if current.present?
        chunks.concat(split_paragraph(para))
        current = +""
      elsif current.bytesize + para.bytesize + 1 < MAX_CHUNK_BYTES
        current << " " << para
      else
        chunks << current.strip if current.present?
        current = +para
      end
    end
    chunks << current.strip if current.present?
    chunks.presence
  end

  def split_paragraph(text)
    segments = split_at_punctuation(text)
    segments.flat_map { |s| s.length > MAX_SENTENCE_CHARS ? split_by_length(s) : [ s ] }
  end

  def split_at_punctuation(text)
    text.split(/(?<=[。．！？.!?])/).map(&:strip).reject(&:blank?).presence || [ text ]
  end

  def split_by_length(text)
    text.scan(/.{1,#{MAX_SENTENCE_CHARS}}/m).map(&:strip).reject(&:blank?)
  end
end
