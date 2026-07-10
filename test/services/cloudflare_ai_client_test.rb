require "test_helper"

class CloudflareAiClientTest < ActiveSupport::TestCase
  setup do
    @client = CloudflareAiClient.new(
      account_id: "test_account",
      api_token: "test_token",
      model: "test-model"
    )
  end

  test "extracts text from openai chat completions format" do
    payload = {
      "result" => {
        "choices" => [
          { "message" => { "content" => "{\"title\":\"Test\",\"body\":\"Hello\",\"excerpt\":\"Hi\"}" } }
        ],
        "response" => { "title" => "Test", "body" => "Hello", "excerpt" => "Hi" }
      },
      "success" => true
    }

    text = @client.send(:extract_text, payload)
    assert_equal "{\"title\":\"Test\",\"body\":\"Hello\",\"excerpt\":\"Hi\"}", text
  end

  test "extracts text from traditional text generation format" do
    payload = {
      "result" => {
        "response" => "{\"title\":\"Test\",\"body\":\"Hello\",\"excerpt\":\"Hi\"}"
      },
      "success" => true
    }

    text = @client.send(:extract_text, payload)
    assert_equal "{\"title\":\"Test\",\"body\":\"Hello\",\"excerpt\":\"Hi\"}", text
  end

  test "extracts text from result as direct string" do
    payload = {
      "result" => "{\"title\":\"Test\",\"body\":\"Hello\",\"excerpt\":\"Hi\"}",
      "success" => true
    }

    text = @client.send(:extract_text, payload)
    assert_equal "{\"title\":\"Test\",\"body\":\"Hello\",\"excerpt\":\"Hi\"}", text
  end

  test "returns nil for blank result" do
    payload = { "result" => nil, "success" => true }
    assert_nil @client.send(:extract_text, payload)

    payload = { "result" => "", "success" => true }
    assert_nil @client.send(:extract_text, payload)
  end

  test "returns nil when all text sources are empty" do
    payload = {
      "result" => { "choices" => [ { "message" => { "content" => nil } } ], "response" => "", "text" => nil },
      "success" => true
    }
    assert_nil @client.send(:extract_text, payload)
  end

  test "simulates qwen model response format reproducing the bug" do
    payload = {
      "result" => {
        "choices" => [
          {
            "finish_reason" => "stop",
            "index" => 0,
            "message" => {
              "content" => "\n\n{\n  \"title\": \"English Title\",\n  \"body\": \"## Heading\\n\\nBody text\",\n  \"excerpt\": \"Summary\"\n}",
              "role" => "assistant"
            }
          }
        ],
        "response" => {
          "title" => "English Title",
          "body" => "## Heading\n\nBody text",
          "excerpt" => "Summary"
        }
      },
      "success" => true
    }

    text = @client.send(:extract_text, payload)
    assert text.is_a?(String), "extract_text should return a String, got #{text.class}"
    parsed = JSON.parse(text)
    assert_equal "English Title", parsed["title"]
    assert_equal "Summary", parsed["excerpt"]
  end
end
