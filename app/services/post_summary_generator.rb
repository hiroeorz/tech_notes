class PostSummaryGenerator
  class InvalidInput < StandardError; end
  class GenerationError < StandardError; end
  class RateLimitError < GenerationError; end

  MAX_BODY_CHARS = 12_000
  MAX_SUMMARY_CHARS = 100

  def initialize(client: CloudflareAiClient.new)
    @client = client
  end

  def generate(title:, body:)
    raise InvalidInput, "Please enter body text before generating a summary." if body.to_s.strip.blank?

    normalize_summary(@client.run(messages: messages(title: title, body: body)))
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
          You are an assistant that helps edit technical articles for Hiroe Tech Notes.
          Create a summary of the article based only on the given title and body,
          in the same language as the article.
          Do not add facts not present in the body.
          Do not use Markdown, HTML, bullet points, headings, quotes, or introductory text.
          End the summary with a period.
          Output only the summary text.
        PROMPT
      },
      {
        role: "user",
        content: <<~PROMPT
          Summarize the following article in one paragraph of 70 to 90 characters,
          in the same language as the article.
          Do not include URLs, code details, or Markdown syntax.

          [Title]
          #{title.to_s.strip.presence || "Untitled"}

          [Body]
          #{body.to_s.first(MAX_BODY_CHARS)}
        PROMPT
      }
    ]
  end

  def normalize_summary(value)
    summary = value.to_s.strip.gsub(/\s+/, " ")
    summary = summary.delete_prefix("要約:").delete_prefix("要約：").strip
    summary = summary[1...-1].strip if wrapped_with_quote?(summary)

    raise GenerationError, "Could not get a summary from the AI." if summary.blank?
    raise GenerationError, "AI returned unexpected HTML." if summary.match?(/<[^>]+>/)

    truncate_at_sentence_boundary(summary)
  end

  def wrapped_with_quote?(summary)
    (summary.start_with?("\"") && summary.end_with?("\"")) ||
      (summary.start_with?("「") && summary.end_with?("」"))
  end

  def truncate_at_sentence_boundary(summary)
    return summary if summary.length <= MAX_SUMMARY_CHARS

    boundary_index = summary.first(MAX_SUMMARY_CHARS).rindex(/[.!?。！？]/)
    return summary.first(boundary_index + 1) if boundary_index

    raise GenerationError, "AI could not generate a short enough summary. Please try again."
  end
end
