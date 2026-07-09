require "test_helper"

class PostSlugGeneratorTest < ActiveSupport::TestCase
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

  test "generates a normalized English kebab-case slug from Japanese content" do
    client = CapturingClient.new(response: "Slug: aurora-postgresql-onprem-migration-access")
    slug = PostSlugGenerator.new(client: client).generate(
      title: "Aurora PostgreSQLへオンプレから移行期間中に接続する",
      body: "AWSでAurora for PostgreSQLを使い、移行期間中はオンプレからもアクセスします。"
    )

    assert_equal "aurora-postgresql-onprem-migration-access", slug
    assert_includes client.messages.dig(0, :content), "English slug"
    assert_includes client.messages.dig(0, :content), "ASCII lowercase"
    assert_includes client.messages.dig(1, :content), "[Title]"
    assert_includes client.messages.dig(1, :content), "[Body]"
  end

  test "rejects blank title and body before calling ai client" do
    assert_raises(PostSlugGenerator::InvalidInput) do
      PostSlugGenerator.new(client: ExplodingClient.new).generate(title: " ", body: " ")
    end
  end

  test "rejects japanese-only slug output" do
    error = assert_raises(PostSlugGenerator::GenerationError) do
      PostSlugGenerator.new(client: CapturingClient.new(response: "日本語のスラッグ")).generate(title: "タイトル", body: "本文")
    end

    assert_includes error.message, "valid English slug"
  end

  test "limits generated slug length and preserves slug format" do
    slug = PostSlugGenerator.new(client: CapturingClient.new(response: "very-long-#{'slug-' * 30}ending")).generate(title: "タイトル", body: "本文")

    assert_operator slug.length, :<=, PostSlugGenerator::MAX_SLUG_CHARS
    assert_match(/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/, slug)
  end

  test "converts cloudflare request failures to generation errors" do
    error = assert_raises(PostSlugGenerator::GenerationError) do
      PostSlugGenerator.new(client: FailingClient.new).generate(title: "タイトル", body: "本文")
    end

    assert_includes error.message, "timed out"
  end

  test "preserves cloudflare rate limit errors" do
    error = assert_raises(PostSlugGenerator::RateLimitError) do
      PostSlugGenerator.new(client: RateLimitedClient.new).generate(title: "タイトル", body: "本文")
    end

    assert_includes error.message, "Rate limit"
  end
end
