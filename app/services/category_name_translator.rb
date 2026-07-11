class CategoryNameTranslator
  class InvalidInput < StandardError; end
  class GenerationError < StandardError; end
  class RateLimitError < GenerationError; end

  def initialize(client: CloudflareAiClient.new)
    @client = client
  end

  def generate(name:)
    raise InvalidInput, "Please enter a category name before translating." if name.to_s.strip.blank?

    normalize_translation(@client.run(messages: messages(name: name)))
  rescue CloudflareAiClient::RateLimitError => error
    raise RateLimitError, error.message
  rescue CloudflareAiClient::ConfigurationError => error
    raise GenerationError, error.message
  rescue CloudflareAiClient::RequestError => error
    raise GenerationError, error.message
  end

  private

  def messages(name:)
    [
      {
        role: "system",
        content: <<~PROMPT.squish
          You translate Japanese category names for a technical blog into English.
          Return only one English translation without quotes, markdown, or explanations.
          Keep it concise and natural as a category label.
        PROMPT
      },
      {
        role: "user",
        content: <<~PROMPT
          Translate this Japanese category name to English:

          [Name]
          #{name.strip}
        PROMPT
      }
    ]
  end

  def normalize_translation(value)
    translation = value.to_s.strip
    translation = translation.delete_prefix("translation:").delete_prefix("translation：").strip
    translation = translation[1...-1].strip if wrapped_with_quote?(translation)

    raise GenerationError, "Could not get a valid English translation from the AI." if translation.blank?

    translation
  end

  def wrapped_with_quote?(value)
    (value.start_with?("\"") && value.end_with?("\"")) ||
      (value.start_with?("'") && value.end_with?("'"))
  end
end
