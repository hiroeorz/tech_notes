require "test_helper"

class CategoryNameTranslatorTest < ActiveSupport::TestCase
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
      raise CloudflareAiClient::RequestError, "Connection to Cloudflare Workers AI timed out."
    end
  end

  class RateLimitedClient
    def run(messages:)
      raise CloudflareAiClient::RateLimitError, "Rate limit reached."
    end
  end

  class ExplodingClient
    def run(messages:)
      raise "AI client must not be called"
    end
  end

  test "translates a Japanese category name to English" do
    client = CapturingClient.new(response: "Infrastructure")
    translation = CategoryNameTranslator.new(client: client).generate(name: "インフラ")

    assert_equal "Infrastructure", translation
    assert_includes client.messages.dig(0, :content), "translate"
    assert_includes client.messages.dig(1, :content), "[Name]"
    assert_includes client.messages.dig(1, :content), "インフラ"
  end

  test "rejects blank name before calling ai client" do
    assert_raises(CategoryNameTranslator::InvalidInput) do
      CategoryNameTranslator.new(client: ExplodingClient.new).generate(name: " ")
    end
  end

  test "strips prefix from translation output" do
    translation = CategoryNameTranslator.new(client: CapturingClient.new(response: "translation: Automation")).generate(name: "自動化")
    assert_equal "Automation", translation
  end

  test "strips quotes from translation output" do
    translation = CategoryNameTranslator.new(client: CapturingClient.new(response: "\"Security\"")).generate(name: "セキュリティ")
    assert_equal "Security", translation
  end

  test "detects blank translation as generation error" do
    error = assert_raises(CategoryNameTranslator::GenerationError) do
      CategoryNameTranslator.new(client: CapturingClient.new(response: " ")).generate(name: "ポエム")
    end

    assert_includes error.message, "valid English translation"
  end

  test "converts cloudflare request failures to generation errors" do
    error = assert_raises(CategoryNameTranslator::GenerationError) do
      CategoryNameTranslator.new(client: FailingClient.new).generate(name: "インフラ")
    end

    assert_includes error.message, "timed out"
  end

  test "preserves cloudflare rate limit errors" do
    error = assert_raises(CategoryNameTranslator::RateLimitError) do
      CategoryNameTranslator.new(client: RateLimitedClient.new).generate(name: "インフラ")
    end

    assert_includes error.message, "Rate limit"
  end
end
