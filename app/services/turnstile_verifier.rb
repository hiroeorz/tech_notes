class TurnstileVerifier
  VERIFY_URL = "https://challenges.cloudflare.com/turnstile/v0/siteverify".freeze

  def self.verify(token, remote_ip: nil)
    if test_mode?
      return true if token.present?
      return false
    end

    secret = ENV["TURNSTILE_SECRET_KEY"].to_s
    return false if secret.blank?

    body = { secret: secret, response: token }
    body[:remoteip] = remote_ip if remote_ip

    uri = URI(VERIFY_URL)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 5
    http.open_timeout = 5

    response = http.post(uri.path, URI.encode_www_form(body), { "Content-Type" => "application/x-www-form-urlencoded" })
    result = JSON.parse(response.body)
    result["success"] == true
  rescue StandardError => e
    Rails.logger.error("Turnstile verification failed: #{e.message}")
    false
  end

  def self.test_mode?
    Rails.env.test? || Rails.env.development?
  end
end
