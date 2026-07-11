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
    assert_equal "ja-JP-Chirp3-HD-Despina", entry[:name]
  end

  test "voice map has en entry" do
    entry = GoogleTtsClient::VOICE_MAP["en"]
    assert_equal "en-US", entry[:language_code]
    assert_equal "en-US-Chirp3-HD-Despina", entry[:name]
  end

  test "split_sentence returns short sentence as-is" do
    client = GoogleTtsClient.new(api_key: "test-key")
    result = client.send(:split_sentence, "短い文です。")
    assert_equal [ "短い文です。" ], result
  end

  test "split_sentence splits long sentence at comma" do
    client = GoogleTtsClient.new(api_key: "test-key")
    long = "あ" * 60 + "、" + "い" * 60 + "。"
    result = client.send(:split_sentence, long)
    assert_equal 2, result.size
    assert result.all? { |s| s.length <= GoogleTtsClient::MAX_SENTENCE_LENGTH }
  end

  test "split_sentence splits long sentence at space" do
    client = GoogleTtsClient.new(api_key: "test-key")
    long = "Hello " * 30
    result = client.send(:split_sentence, long)
    assert result.all? { |s| s.length <= GoogleTtsClient::MAX_SENTENCE_LENGTH }
  end

  test "split_sentence splits long sentence without delimiter at exact boundary" do
    client = GoogleTtsClient.new(api_key: "test-key")
    long = "あ" * 250
    result = client.send(:split_sentence, long)
    assert result.all? { |s| s.length <= GoogleTtsClient::MAX_SENTENCE_LENGTH }
    assert result.size >= 2
  end

  test "ssml_wrap wraps short text in speak and s tags" do
    client = GoogleTtsClient.new(api_key: "test-key")
    ssml = client.send(:ssml_wrap, "短い文です。")
    assert_match %r{\A<speak>}, ssml
    assert_match %r{</speak>\z}, ssml
    assert_includes ssml, "<s>短い文です。</s>"
  end

  test "ssml_wrap escapes special characters" do
    client = GoogleTtsClient.new(api_key: "test-key")
    ssml = client.send(:ssml_wrap, "A & B < C > D \"E\" 'F'")
    assert_includes ssml, "&amp;"
    assert_includes ssml, "&lt;"
    assert_includes ssml, "&gt;"
    assert_includes ssml, "&quot;"
    assert_includes ssml, "&apos;"
  end
end
