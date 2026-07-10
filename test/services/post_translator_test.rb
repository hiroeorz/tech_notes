require "test_helper"

class PostTranslatorTest < ActiveSupport::TestCase
  class CapturingClient
    attr_reader :messages

    def initialize(response:)
      @response = response
    end

    def run(messages:)
      @messages = messages
      @response
    end
  end

  class FailingClient
    def run(messages:)
      raise CloudflareAiClient::RequestError, "AI request failed"
    end
  end

  test "translates all article fields from structured json" do
    client = CapturingClient.new(response: <<~JSON)
      ```json
      {"title":"English title","body":"## Heading\\n\\n```ruby\\nputs :ok\\n```","excerpt":"English excerpt"}
      ```
    JSON

    result = PostTranslator.new(client: client).translate(
      title: "日本語タイトル",
      body: "## 見出し\n\n```ruby\nputs :ok\n```",
      excerpt: "日本語要約",
      source_locale: :ja,
      target_locale: :en
    )

    assert_equal "English title", result[:title]
    assert_equal "English excerpt", result[:excerpt]
    assert_includes result[:body], "puts :ok"
    assert_includes client.messages.dig(0, :content), "Preserve Markdown structure"
    assert_equal "日本語タイトル", JSON.parse(client.messages.dig(1, :content)).fetch("title")
  end

  test "rejects invalid json and incomplete fields" do
    translator = PostTranslator.new(client: CapturingClient.new(response: "not json"))
    assert_raises(PostTranslator::TranslationError) do
      translator.translate(title: "a", body: "b", excerpt: "c", source_locale: :en, target_locale: :ja)
    end

    translator = PostTranslator.new(client: CapturingClient.new(response: '{"title":"a","body":"b"}'))
    assert_raises(PostTranslator::TranslationError) do
      translator.translate(title: "a", body: "b", excerpt: "c", source_locale: :en, target_locale: :ja)
    end

    translator = PostTranslator.new(client: CapturingClient.new(response: "[]"))
    assert_raises(PostTranslator::TranslationError) do
      translator.translate(title: "a", body: "b", excerpt: "c", source_locale: :en, target_locale: :ja)
    end
  end

  test "converts cloudflare failures to translation errors" do
    assert_raises(PostTranslator::TranslationError) do
      PostTranslator.new(client: FailingClient.new).translate(
        title: "a",
        body: "b",
        excerpt: "c",
        source_locale: :en,
        target_locale: :ja
      )
    end
  end

  test "rejects unsupported or identical locales before calling the ai" do
    translator = PostTranslator.new(client: CapturingClient.new(response: "{}"))

    assert_raises(ArgumentError) do
      translator.translate(title: "a", body: "b", excerpt: "c", source_locale: :en, target_locale: :en)
    end
    assert_raises(ArgumentError) do
      translator.translate(title: "a", body: "b", excerpt: "c", source_locale: :fr, target_locale: :en)
    end
  end
end
