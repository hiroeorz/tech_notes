require "json"
require "net/http"
require "uri"

class CloudflareAiClient
  class ConfigurationError < StandardError; end
  class RequestError < StandardError; end
  class RateLimitError < RequestError; end

  DEFAULT_TIMEOUT_SECONDS = 60

  def initialize(
    account_id: self.class.config_value(:account_id, "CLOUDFLARE_ACCOUNT_ID"),
    api_token: self.class.config_value(:api_token, "CLOUDFLARE_AI_API_TOKEN"),
    model: self.class.config_value(:model, "CLOUDFLARE_AI_MODEL"),
    timeout_seconds: self.class.config_value(:timeout_seconds, "CLOUDFLARE_AI_TIMEOUT_SECONDS")
  )
    @account_id = account_id.to_s
    @api_token = api_token.to_s
    @model = model.to_s
    @timeout_seconds = timeout_seconds.presence || DEFAULT_TIMEOUT_SECONDS
  end

  def self.configured?
    new.configured?
  end

  def self.config_value(key, env_name)
    ENV[env_name].presence || Rails.application.credentials.dig(:cloudflare, :ai, key)
  end

  def configured?
    @account_id.present? && @api_token.present? && @model.present?
  end

  def run(messages:)
    raise ConfigurationError, "Cloudflare Workers AI is not configured." unless configured?

    response = perform_request(messages)
    payload = JSON.parse(response.body)
    raise RateLimitError, cloudflare_error_message(payload) if response.code.to_i == 429
    raise RequestError, cloudflare_error_message(payload) unless response.is_a?(Net::HTTPSuccess) && payload["success"] != false

    extract_text(payload).presence || raise(RequestError, "Could not get a response from Cloudflare Workers AI.")
  rescue JSON::ParserError
    raise RequestError, "Could not parse Cloudflare Workers AI response."
  rescue Net::OpenTimeout, Net::ReadTimeout
    raise RequestError, "Connection to Cloudflare Workers AI timed out."
  rescue SocketError, SystemCallError => error
    raise RequestError, "Could not connect to Cloudflare Workers AI."
  end

  private

  def perform_request(messages)
    uri = URI("https://api.cloudflare.com/client/v4/accounts/#{@account_id}/ai/run/#{@model}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = timeout_seconds
    http.read_timeout = timeout_seconds

    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{@api_token}"
    request["Content-Type"] = "application/json"
    request.body = JSON.generate(messages: messages)

    http.request(request)
  end

  def timeout_seconds
    Integer(@timeout_seconds)
  rescue ArgumentError, TypeError
    DEFAULT_TIMEOUT_SECONDS
  end

  def extract_text(payload)
    result = payload["result"]
    return result if result.is_a?(String)
    return if result.blank?

    result["response"] ||
      result["text"] ||
      result.dig("choices", 0, "message", "content")
  end

  def cloudflare_error_message(payload)
    errors = Array(payload["errors"]).filter_map do |error|
      next error.to_s unless error.is_a?(Hash)

      [ error["code"], error["message"] ].compact.join(": ").presence
    end
    errors.presence&.join(" / ") || "Cloudflare Workers AI call failed."
  end
end
