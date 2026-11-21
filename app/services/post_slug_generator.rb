class PostSlugGenerator
  class InvalidInput < StandardError; end
  class GenerationError < StandardError; end
  class RateLimitError < GenerationError; end

  MAX_BODY_CHARS = 4_000
  MAX_SLUG_CHARS = 80
  MAX_OUTPUT_TOKENS = 64
  CHAT_TEMPLATE_KWARGS = { enable_thinking: false }.freeze

  def initialize(client: CloudflareAiClient.new)
    @client = client
  end

  def generate(title:, body:)
    raise InvalidInput, "Please enter a title or body before generating a slug." if title.to_s.strip.blank? && body.to_s.strip.blank?

    normalize_slug(@client.run(
      messages: messages(title: title, body: body),
      max_tokens: MAX_OUTPUT_TOKENS,
      chat_template_kwargs: CHAT_TEMPLATE_KWARGS
    ))
  rescue CloudflareAiClient::RateLimitError => error
    raise RateLimitError, error.message
  rescue CloudflareAiClient::ConfigurationError => error
    raise GenerationError, error.message
  rescue CloudflareAiClient::RequestError => error
    raise GenerationError, error.message
  end

  private

  def messages(title:, body:)
    [
      {
        role: "system",
        content: <<~PROMPT.squish
          You create URL slugs for a Japanese technical blog.
          Return only one English slug in lowercase kebab-case.
          Use ASCII lowercase letters, numbers, and hyphens only.
          Do not use Japanese words, markdown, quotes, explanations, prefixes, or suffixes.
        PROMPT
      },
      {
        role: "user",
        content: <<~PROMPT
          Create a concise English slug for this article.
          The slug must be 3 to 8 words, descriptive, and based only on the title and body.

          [Title]
          #{title.to_s.strip.presence || "Untitled"}

          [Body]
          #{body.to_s.first(MAX_BODY_CHARS)}
        PROMPT
      }
    ]
  end

  def normalize_slug(value)
    slug = strip_thinking_block(value).downcase
    slug = slug.delete_prefix("slug:").delete_prefix("slug：").strip
    slug = slug[1...-1].strip if wrapped_with_quote?(slug)
    slug = slug.gsub(/[^a-z0-9-]+/, "-").gsub(/-+/, "-").delete_prefix("-").delete_suffix("-")
    slug = slug.first(MAX_SLUG_CHARS).delete_suffix("-")

    raise GenerationError, "Could not get a valid English slug from the AI." unless slug.match?(/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/)

    slug
  end

  def strip_thinking_block(value)
    value.to_s.gsub(/<\|channel>thought.*?<channel\|>/m, "").strip
  end

  def wrapped_with_quote?(slug)
    (slug.start_with?("\"") && slug.end_with?("\"")) ||
      (slug.start_with?("'") && slug.end_with?("'")) ||
      (slug.start_with?("`") && slug.end_with?("`"))
  end
end
