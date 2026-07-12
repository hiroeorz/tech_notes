class ProfileTranslator
  class InvalidInput < StandardError; end
  class GenerationError < StandardError; end
  class RateLimitError < GenerationError; end

  def initialize(client: CloudflareAiClient.new)
    @client = client
  end

  def translate(profile_title:, profile_bio:)
    raise InvalidInput, "Profile title and bio must not be blank." if profile_title.to_s.strip.blank? && profile_bio.to_s.strip.blank?

    result = @client.run(messages: messages(profile_title: profile_title, profile_bio: profile_bio))
    parse_result(result)
  rescue CloudflareAiClient::RateLimitError => error
    raise RateLimitError, error.message
  rescue CloudflareAiClient::ConfigurationError => error
    raise GenerationError, error.message
  rescue CloudflareAiClient::RequestError => error
    raise GenerationError, error.message
  end

  private

  def messages(profile_title:, profile_bio:)
    [
      {
        role: "system",
        content: <<~PROMPT.squish
          You translate a Japanese tech blogger's profile into natural English.
          You will receive a JSON object with "profile_title" and "profile_bio".
          Return only a valid JSON object with the same keys and their English translations.
          Keep titles concise and bios natural-sounding. Do not include markdown, code fences, or explanations.
        PROMPT
      },
      {
        role: "user",
        content: <<~PROMPT
          Translate this Japanese profile to English:

          {"profile_title": "#{profile_title.strip}", "profile_bio": "#{profile_bio.strip}"}
        PROMPT
      }
    ]
  end

  def parse_result(value)
    text = value.to_s.strip
    json = text.sub(/\A```(?:json)?\s*/, "").sub(/\s*```\z/, "")
    parsed = JSON.parse(json)
    title = parsed["profile_title_en"].to_s.strip
    title = parsed["profile_title"].to_s.strip if title.blank?
    bio = parsed["profile_bio_en"].to_s.strip
    bio = parsed["profile_bio"].to_s.strip if bio.blank?
    raise GenerationError, "Could not get a valid English translation from the AI." if title.blank? && bio.blank?

    { profile_title_en: title, profile_bio_en: bio }
  rescue JSON::ParserError
    raise GenerationError, "Could not parse AI response as JSON."
  end
end
