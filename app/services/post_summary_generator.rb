class PostSummaryGenerator
  class InvalidInput < StandardError; end
  class GenerationError < StandardError; end
  class RateLimitError < GenerationError; end

  MAX_BODY_CHARS = 12_000
  MAX_SUMMARY_CHARS = 200

  def initialize(client: CloudflareAiClient.new)
    @client = client
  end

  def generate(title:, body:)
    raise InvalidInput, "本文を入力してから要約を生成してください。" if body.to_s.strip.blank?

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
          あなたは Hiroe Tech Notes の技術記事編集を補助する日本語編集者です。
          与えられたタイトルと本文だけを根拠に、記事の要約を作成してください。
          本文にない事実は追加しないでください。
          Markdown、HTML、箇条書き、見出し、引用符、前置き文は使わないでください。
          出力は要約本文のみとしてください。
        PROMPT
      },
      {
        role: "user",
        content: <<~PROMPT
          次の記事を日本語で100から160字程度の1段落に要約してください。
          URLの羅列、コードの詳細、Markdown記法は要約に含めないでください。

          [タイトル]
          #{title.to_s.strip.presence || "無題"}

          [本文]
          #{body.to_s.first(MAX_BODY_CHARS)}
        PROMPT
      }
    ]
  end

  def normalize_summary(value)
    summary = value.to_s.strip.gsub(/\s+/, " ")
    summary = summary.delete_prefix("要約:").delete_prefix("要約：").strip
    summary = summary[1...-1].strip if wrapped_with_quote?(summary)

    raise GenerationError, "Cloudflare Workers AIから要約を取得できませんでした。" if summary.blank?
    raise GenerationError, "AIが想定外のHTMLを返しました。" if summary.match?(/<[^>]+>/)

    summary.first(MAX_SUMMARY_CHARS)
  end

  def wrapped_with_quote?(summary)
    (summary.start_with?("\"") && summary.end_with?("\"")) ||
      (summary.start_with?("「") && summary.end_with?("」"))
  end
end
