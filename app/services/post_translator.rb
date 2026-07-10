require "json"

class PostTranslator
  class TranslationError < StandardError; end

  def initialize(client: CloudflareAiClient.new)
    @client = client
  end

  def translate(title:, body:, excerpt:, source_locale:, target_locale:)
    validate_locales!(source_locale, target_locale)
    parse_response(@client.run(messages: messages(
      title: title,
      body: body,
      excerpt: excerpt,
      source_locale: source_locale,
      target_locale: target_locale
    )))
  rescue CloudflareAiClient::ConfigurationError, CloudflareAiClient::RequestError => error
    raise TranslationError, error.message
  end

  private

  def validate_locales!(source_locale, target_locale)
    locales = [ source_locale.to_s, target_locale.to_s ]
    unless locales.all? { |locale| locale.in?(PostTranslation::SUPPORTED_LOCALES) } && locales.uniq.size == 2
      raise ArgumentError, "Source and target locales must be different supported locales."
    end
  end

  def messages(title:, body:, excerpt:, source_locale:, target_locale:)
    [
      {
        role: "system",
        content: <<~PROMPT.squish
          You translate technical articles for Hiroe Tech Notes.
          Translate only natural-language prose from #{source_locale} to #{target_locale}.
          Preserve Markdown structure, headings, lists, tables, links, image destinations,
          HTML, code fences, inline code, commands, identifiers, and URLs exactly unless their
          human-readable labels require translation. Do not add, remove, summarize, or reorder content.
          Return only a valid JSON object with the string keys title, body, and excerpt.
        PROMPT
      },
      {
        role: "user",
        content: JSON.generate(title: title.to_s, body: body.to_s, excerpt: excerpt.to_s)
      }
    ]
  end

  def parse_response(response)
    payload = JSON.parse(strip_json_fence(response.to_s.strip))
    raise TranslationError, "AI translation response was not a JSON object." unless payload.is_a?(Hash)

    translated = %w[title body excerpt].to_h do |key|
      value = payload[key]
      raise TranslationError, "AI translation response has an invalid #{key}." unless value.is_a?(String) && value.present?

      [ key.to_sym, value ]
    end
    translated
  rescue JSON::ParserError
    raise TranslationError, "AI translation response was not valid JSON."
  end

  def strip_json_fence(response)
    response.sub(/\A```(?:json)?\s*/i, "").sub(/\s*```\z/, "")
  end
end
