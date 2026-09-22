# typed: true

class OauthMetadataController < ActionController::API
  def show
    render(json: {
      issuer: request.base_url,
      authorization_endpoint: oauth_authorization_url,
      token_endpoint: oauth_token_url,
      revocation_endpoint: oauth_revoke_url,
      response_types_supported: %w[code],
      grant_types_supported: %w[authorization_code refresh_token],
      code_challenge_methods_supported: Doorkeeper.config.pkce_code_challenge_methods_supported.presence || %w[S256],
      scopes_supported: Doorkeeper.config.scopes.to_a,
      token_endpoint_auth_methods_supported: %w[client_secret_basic client_secret_post none]
    })
  end
end
