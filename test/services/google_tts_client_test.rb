require "test_helper"

class GoogleTtsClientTest < ActiveSupport::TestCase
  test "raises on unsupported locale" do
    client = GoogleTtsClient.new(api_key: "test-key")
    assert_raises(ArgumentError) { client.synthesize(text: "hello", locale: "fr") }
  end

  test "raises configuration error when no api key" do
    assert_raises(GoogleTtsClient::ConfigurationError) do
      GoogleTtsClient.new(api_key: "").synthesize(text: "hello", locale: "en")
    end
  end

  test "configured? returns false without api key" do
    assert_not GoogleTtsClient.new(api_key: "").configured?
  end

  test "configured? returns true with api key" do
    assert GoogleTtsClient.new(api_key: "key").configured?
  end

  test "voice map has ja entry" do
    entry = GoogleTtsClient::VOICE_MAP["ja"]
    assert_equal "ja-JP", entry[:language_code]
    assert_equal "ja-JP-Neural2-C", entry[:name]
  end

  test "voice map has en entry" do
    entry = GoogleTtsClient::VOICE_MAP["en"]
    assert_equal "en-US", entry[:language_code]
    assert_equal "en-US-Neural2-C", entry[:name]
  end
end
