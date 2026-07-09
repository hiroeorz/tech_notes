require "test_helper"

class PostSummaryGeneratorTest < ActiveSupport::TestCase
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

  test "generates a normalized summary from title and body" do
    client = CapturingClient.new(response: " 要約：Terraform のリモートステート設計について、構成例と運用時の注意点を整理した記事です。 ")
    summary = PostSummaryGenerator.new(client: client).generate(
      title: "Terraformのリモートステート設計",
      body: "## 構成例\nS3 と DynamoDB を使います。"
    )

    assert_equal "Terraform のリモートステート設計について、構成例と運用時の注意点を整理した記事です。", summary
    assert_includes client.messages.dig(0, :content), "Do not add facts not present in the body"
    assert_includes client.messages.dig(1, :content), "[Title]"
    assert_includes client.messages.dig(1, :content), "Terraformのリモートステート設計"
    assert_includes client.messages.dig(1, :content), "[Body]"
  end

  test "rejects blank body before calling the ai client" do
    assert_raises(PostSummaryGenerator::InvalidInput) do
      PostSummaryGenerator.new(client: ExplodingClient.new).generate(title: "タイトル", body: " ")
    end
  end

  test "limits body sent to cloudflare workers ai" do
    long_body = "a" * (PostSummaryGenerator::MAX_BODY_CHARS + 50)
    client = CapturingClient.new(response: "長文記事の要点を短く整理した要約です。")

    PostSummaryGenerator.new(client: client).generate(title: "長文", body: long_body)

    sent_body = client.messages.dig(1, :content).split("[Body]", 2).last
    assert_operator sent_body.length, :<=, PostSummaryGenerator::MAX_BODY_CHARS + 10
  end

  test "converts cloudflare request failures to generation errors" do
    error = assert_raises(PostSummaryGenerator::GenerationError) do
      PostSummaryGenerator.new(client: FailingClient.new).generate(title: "タイトル", body: "本文")
    end

    assert_includes error.message, "timed out"
  end

  test "preserves cloudflare rate limit errors" do
    error = assert_raises(PostSummaryGenerator::RateLimitError) do
      PostSummaryGenerator.new(client: RateLimitedClient.new).generate(title: "タイトル", body: "本文")
    end

    assert_includes error.message, "Rate limit"
  end

  test "truncates generated summaries at sentence boundary under one hundred characters" do
    client = CapturingClient.new(response: "#{"あ" * 80}。#{"い" * 40}。")
    summary = PostSummaryGenerator.new(client: client).generate(title: "タイトル", body: "本文")

    assert_equal "#{"あ" * 80}。", summary
  end

  test "rejects overlong summaries without a sentence boundary" do
    error = assert_raises(PostSummaryGenerator::GenerationError) do
      PostSummaryGenerator.new(client: CapturingClient.new(response: "あ" * 120)).generate(title: "タイトル", body: "本文")
    end

    assert_includes error.message, "short enough summary"
  end

  test "rejects html output" do
    error = assert_raises(PostSummaryGenerator::GenerationError) do
      PostSummaryGenerator.new(client: CapturingClient.new(response: "<p>本文です</p>")).generate(title: "タイトル", body: "本文")
    end

    assert_includes error.message, "HTML"
  end
end
