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

  test "default max_tokens is applied when not specified" do
    client = CloudflareAiClient.new(account_id: "a", api_token: "b", model: "c")
    body = client.send(:request_body, [ { role: "user", content: "hi" } ])
    parsed = JSON.parse(body)
    assert_equal 8192, parsed["max_tokens"]
  end

  test "passes max_tokens in request body" do
    client = CloudflareAiClient.new(
      account_id: "a", api_token: "b", model: "c", max_tokens: 4096
    )
    body = client.send(:request_body, [ { role: "user", content: "hi" } ])
    parsed = JSON.parse(body)
    assert_equal 4096, parsed["max_tokens"]
  end

  test "falls back to default when max_tokens is invalid" do
    client = CloudflareAiClient.new(
      account_id: "a", api_token: "b", model: "c", max_tokens: "abc"
    )
    assert_equal 8192, client.send(:max_tokens)
  end

  test "passes per-request options to the request body" do
    body = @client.send(
      :request_body,
      [ { role: "user", content: "hi" } ],
      max_tokens: 64,
      chat_template_kwargs: { enable_thinking: false }
    )
    parsed = JSON.parse(body)

    assert_equal 64, parsed["max_tokens"]
    assert_equal({ "enable_thinking" => false }, parsed["chat_template_kwargs"])
  end

  test "default timeout is 120 seconds" do
    client = CloudflareAiClient.new(
      account_id: "a", api_token: "b", model: "c", timeout_seconds: nil
    )
    assert_equal 120, client.send(:timeout_seconds)
  end

  test "falls back to default when timeout is invalid" do
    client = CloudflareAiClient.new(
      account_id: "a", api_token: "b", model: "c", timeout_seconds: "abc"
    )
    assert_equal 120, client.send(:timeout_seconds)
  end

  test "caps connect and write timeouts to leave room for the response" do
    client = CloudflareAiClient.new(
      account_id: "a", api_token: "b", model: "c", timeout_seconds: 120
    )
    assert_equal 10, client.send(:open_timeout_seconds)
    assert_equal 30, client.send(:write_timeout_seconds)
  end

  test "does not let connect and write timeouts exceed the configured timeout" do
    client = CloudflareAiClient.new(
      account_id: "a", api_token: "b", model: "c", timeout_seconds: 5
    )
    assert_equal 5, client.send(:open_timeout_seconds)
    assert_equal 5, client.send(:write_timeout_seconds)
  end

  test "raises error when finish_reason is length" do
    payload = {
      "result" => {
        "choices" => [
          {
            "finish_reason" => "length",
            "message" => { "content" => "{\"title\":\"Partial\"}" }
          }
        ]
      },
      "success" => true
    }

    assert_raises(CloudflareAiClient::RequestError) do
      @client.send(:check_truncation!, payload)
    end
  end

  test "does not raise when finish_reason is stop" do
    payload = {
      "result" => {
        "choices" => [
          { "finish_reason" => "stop", "message" => { "content" => "ok" } }
        ]
      },
      "success" => true
    }

    assert_nothing_raised do
      @client.send(:check_truncation!, payload)
    end
  end

  class StubClient < CloudflareAiClient
    def initialize(response:, **kwargs)
      @response = response
      super(**kwargs)
    end

    private

    def perform_request(*)
      @response
    end
  end

  test "uses configured max_tokens in run method" do
    response = Struct.new(:code, :body, keyword_init: true) do
      def is_a?(*) = true
    end.new(
      code: "200", body: JSON.generate({
        "result" => {
          "choices" => [ {
            "finish_reason" => "stop",
            "message" => { "content" => "ok" }
          } ]
        },
        "success" => true
      })
    )

    client = StubClient.new(response: response, account_id: "a", api_token: "b", model: "c", max_tokens: 2048)
    result = client.run(messages: [ { role: "user", content: "test" } ])
    assert_equal "ok", result
  end
end
