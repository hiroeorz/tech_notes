require "test_helper"

class ProfileTranslatorTest < ActiveSupport::TestCase
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

  test "translates profile fields from json response" do
    client = CapturingClient.new(response: '{"profile_title_en": "Engineer", "profile_bio_en": "I love coding."}')
    result = ProfileTranslator.new(client: client).translate(profile_title: "エンジニア", profile_bio: "コードが大好きです。")

    assert_equal "Engineer", result[:profile_title_en]
    assert_equal "I love coding.", result[:profile_bio_en]
    assert_includes client.messages.dig(0, :content), "translate"
    assert_includes client.messages.dig(1, :content), "エンジニア"
  end

  test "rejects blank input before calling ai client" do
    assert_raises(ProfileTranslator::InvalidInput) do
      ProfileTranslator.new(client: ExplodingClient.new).translate(profile_title: "", profile_bio: "")
    end
  end

  test "strips markdown code fences from ai response" do
    client = CapturingClient.new(response: "```json\n{\"profile_title_en\": \"Dev\", \"profile_bio_en\": \"Bio\"}\n```")
    result = ProfileTranslator.new(client: client).translate(profile_title: "開発者", profile_bio: "経歴")
    assert_equal "Dev", result[:profile_title_en]
    assert_equal "Bio", result[:profile_bio_en]
  end

  test "detects blank translation as generation error" do
    client = CapturingClient.new(response: '{"profile_title_en": "", "profile_bio_en": ""}')
    error = assert_raises(ProfileTranslator::GenerationError) do
      ProfileTranslator.new(client: client).translate(profile_title: "肩書き", profile_bio: "経歴")
    end
    assert_includes error.message, "valid English translation"
  end

  test "detects invalid json as generation error" do
    client = CapturingClient.new(response: "not json")
    error = assert_raises(ProfileTranslator::GenerationError) do
      ProfileTranslator.new(client: client).translate(profile_title: "肩書き", profile_bio: "経歴")
    end
    assert_includes error.message, "Could not parse"
  end

  test "converts cloudflare request failures to generation errors" do
    error = assert_raises(ProfileTranslator::GenerationError) do
      ProfileTranslator.new(client: FailingClient.new).translate(profile_title: "肩書き", profile_bio: "経歴")
    end
    assert_includes error.message, "timed out"
  end

  test "preserves cloudflare rate limit errors" do
    error = assert_raises(ProfileTranslator::RateLimitError) do
      ProfileTranslator.new(client: RateLimitedClient.new).translate(profile_title: "肩書き", profile_bio: "経歴")
    end
    assert_includes error.message, "Rate limit"
  end
end
