require "json"
require "net/http"
require "uri"
require "base64"

class GoogleTtsClient
  class ConfigurationError < StandardError; end
  class RequestError < StandardError; end

  DEFAULT_TIMEOUT_SECONDS = 60

  VOICE_MAP = {
    "ja" => { language_code: "ja-JP", name: "ja-JP-Neural2-C" },
    "en" => { language_code: "en-US", name: "en-US-Neural2-C" }
  }.freeze

  def initialize(api_key: self.class.config_value)
    @api_key = api_key.to_s
  end

  def self.configured?
    new.configured?
  end

  def self.config_value
    ENV["GOOGLE_CLOUD_API_KEY"].presence || Rails.application.credentials.dig(:google, :cloud, :api_key)
  end

  def configured?
    @api_key.present?
  end

  def synthesize(text:, locale:)
    raise ConfigurationError, "Google Cloud TTS is not configured." unless configured?

    voice_config = VOICE_MAP[locale.to_s]
    raise ArgumentError, "Unsupported locale: #{locale}" unless voice_config

    response = perform_request(text, voice_config)
    payload = JSON.parse(response.body)
    raise RequestError, google_error_message(payload) unless response.is_a?(Net::HTTPSuccess)

    audio_content = payload.dig("audioContent")
    raise RequestError, "No audio content in response." if audio_content.blank?

    Base64.decode64(audio_content)
  rescue JSON::ParserError
    raise RequestError, "Could not parse Google Cloud TTS response."
  rescue Net::OpenTimeout, Net::ReadTimeout
    raise RequestError, "Connection to Google Cloud TTS timed out."
  rescue SocketError, SystemCallError => error
    raise RequestError, "Could not connect to Google Cloud TTS."
  end

  private

  def perform_request(text, voice_config)
    uri = URI("https://texttospeech.googleapis.com/v1/text:synthesize")
    uri.query = URI.encode_www_form(key: @api_key)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = DEFAULT_TIMEOUT_SECONDS
    http.read_timeout = DEFAULT_TIMEOUT_SECONDS

    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request.body = JSON.generate(
      input: { text: text },
      voice: voice_config,
      audioConfig: { audioEncoding: "MP3" }
    )

    http.request(request)
  end

  def google_error_message(payload)
    error = payload.dig("error", "message")
    error.presence || "Google Cloud TTS call failed."
  end
end
