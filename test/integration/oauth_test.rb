require "test_helper"
require "digest"
require "securerandom"
require "base64"
require "uri"

class OauthTest < ActionDispatch::IntegrationTest
  setup do
    @admin = AdminUser.create!(
      email: "admin@example.com",
      password_salt: "salt",
      password_digest: AdminUser.digest_password("password123", "salt")
    )
    @application = Doorkeeper::Application.create!(
      name: "Test Client",
      redirect_uri: "https://client.example.com/callback",
      scopes: "read write",
      confidential: false
    )
  end

  test "authorization code flow with PKCE issues access and refresh tokens" do
    post admin_login_path, params: { email: @admin.email, password: "password123" }
    assert_redirected_to admin_posts_path

    verifier, challenge = pkce_pair
    auth_params = authorization_params(challenge)

    get oauth_authorization_path(auth_params)
    assert_response :success
    assert_includes response.body, @application.name
    assert_includes response.body, I18n.t("oauth.authorize.scopes.read")

    assert_no_difference("Doorkeeper::AccessGrant.count") do
      get oauth_authorization_path(auth_params)
    end

    assert_difference("Doorkeeper::AccessGrant.count", 1) do
      post oauth_authorization_path(auth_params)
    end
    assert_response :redirect
    location = URI.parse(response.headers["Location"])
    assert_equal "client.example.com", location.host
    assert_equal "/callback", location.path
    query = URI.decode_www_form(location.query || "").to_h
    assert query["code"].present?
    assert_equal "test-state", query["state"]

    post oauth_token_path, params: {
      grant_type: "authorization_code",
      code: query["code"],
      redirect_uri: @application.redirect_uri,
      client_id: @application.uid,
      code_verifier: verifier
    }
    assert_response :success
    payload = response.parsed_body
    assert payload["access_token"].present?
    assert payload["refresh_token"].present?
    assert_equal "Bearer", payload["token_type"]
    assert_equal 2.hours.to_i, payload["expires_in"]
    assert_equal "read", payload["scope"]

    post oauth_token_path, params: {
      grant_type: "refresh_token",
      refresh_token: payload["refresh_token"],
      client_id: @application.uid
    }
    assert_response :success
    assert response.parsed_body["access_token"].present?

    post oauth_revoke_path, params: {
      token: payload["access_token"],
      client_id: @application.uid
    }
    assert_response :success
    assert Doorkeeper::AccessToken.find_by(token: payload["access_token"])&.revoked?
  end

  test "authorization request without PKCE is rejected" do
    post admin_login_path, params: { email: @admin.email, password: "password123" }
    assert_redirected_to admin_posts_path

    assert_no_difference("Doorkeeper::AccessGrant.count") do
      get oauth_authorization_path(authorization_params(nil))
    end
    assert_response :bad_request
  end

  test "authorization request with mismatched redirect_uri is rejected" do
    post admin_login_path, params: { email: @admin.email, password: "password123" }
    assert_redirected_to admin_posts_path

    _verifier, challenge = pkce_pair
    assert_no_difference("Doorkeeper::AccessGrant.count") do
      get oauth_authorization_path(authorization_params(challenge).merge(redirect_uri: "https://evil.example.com/callback"))
    end
    assert_response :bad_request
  end

  test "token exchange with wrong verifier is rejected" do
    post admin_login_path, params: { email: @admin.email, password: "password123" }
    assert_redirected_to admin_posts_path

    verifier, challenge = pkce_pair
    post oauth_authorization_path(authorization_params(challenge))
    assert_response :redirect
    code = URI.decode_www_form(URI.parse(response.headers["Location"]).query || "").to_h["code"]
    assert code.present?

    assert_no_difference("Doorkeeper::AccessToken.count") do
      post oauth_token_path, params: {
        grant_type: "authorization_code",
        code: code,
        redirect_uri: @application.redirect_uri,
        client_id: @application.uid,
        code_verifier: "#{verifier}tampered"
      }
    end
    assert_response :bad_request
  end

  test "denied consent redirects with error and issues nothing" do
    post admin_login_path, params: { email: @admin.email, password: "password123" }
    assert_redirected_to admin_posts_path

    _verifier, challenge = pkce_pair
    assert_no_difference("Doorkeeper::AccessGrant.count") do
      delete oauth_authorization_path(authorization_params(challenge))
    end
    assert_response :redirect
    location = URI.parse(response.headers["Location"])
    assert_equal "client.example.com", location.host
    query = URI.decode_www_form(location.query || "").to_h
    assert_equal "access_denied", query["error"]
  end

  test "unauthenticated authorization request redirects to admin login" do
    _verifier, challenge = pkce_pair

    get oauth_authorization_path(authorization_params(challenge))
    assert_redirected_to admin_login_path
    assert_match(%r{\A/oauth/authorize}, session[:return_to])
  end

  test "authorization page renders in Japanese when locale cookie is ja" do
    post admin_login_path, params: { email: @admin.email, password: "password123" }
    assert_redirected_to admin_posts_path

    cookies[:locale] = "ja"

    _verifier, challenge = pkce_pair
    get oauth_authorization_path(authorization_params(challenge))
    assert_response :success
    assert_includes response.body, I18n.t("oauth.authorize.prompt", locale: :ja, client_name: @application.name)
  end

  test "authorization page renders in English by default" do
    post admin_login_path, params: { email: @admin.email, password: "password123" }
    assert_redirected_to admin_posts_path

    _verifier, challenge = pkce_pair
    get oauth_authorization_path(authorization_params(challenge))
    assert_response :success
    assert_includes response.body, I18n.t("oauth.authorize.prompt", locale: :en, client_name: @application.name)
  end

  test "oauth authorization server metadata exposes endpoints and S256" do
    [ "/.well-known/oauth-authorization-server", "/.well-known/oauth-authorization-server/mcp" ].each do |path|
      get path
      assert_response :success
      payload = response.parsed_body
      assert_includes payload["authorization_endpoint"], "/oauth/authorize"
      assert_includes payload["token_endpoint"], "/oauth/token"
      assert_includes payload["revocation_endpoint"], "/oauth/revoke"
      assert_includes payload["response_types_supported"], "code"
      assert_includes payload["code_challenge_methods_supported"], "S256"
      assert_includes payload["grant_types_supported"], "authorization_code"
      assert_includes payload["grant_types_supported"], "refresh_token"
      assert_includes payload["scopes_supported"], "read"
      assert_includes payload["scopes_supported"], "write"
      assert_includes payload["token_endpoint_auth_methods_supported"], "client_secret_basic"
      assert_includes payload["token_endpoint_auth_methods_supported"], "client_secret_post"
      assert_includes payload["token_endpoint_auth_methods_supported"], "none"
      assert payload["issuer"].present?
    end
  end

  test "oauth write token can list tools and create drafts via mcp" do
    access_token = obtain_oauth_token("write")

    post mcp_path, params: { jsonrpc: "2.0", id: 1, method: "tools/list" }.to_json,
      headers: mcp_headers(access_token)
    assert_response :success

    post mcp_path, params: {
      jsonrpc: "2.0", id: 2, method: "tools/call",
      params: { name: "create_draft", arguments: { title: "OAuth draft", body: "OAuth body." } }
    }.to_json, headers: mcp_headers(access_token)
    assert_response :success
    assert_not_includes response.body, access_token
  end

  test "oauth read token is forbidden from calling create_draft via mcp" do
    access_token = obtain_oauth_token("read")

    post mcp_path, params: {
      jsonrpc: "2.0", id: 1, method: "tools/call",
      params: { name: "create_draft", arguments: { title: "OAuth read draft", body: "Body." } }
    }.to_json, headers: mcp_headers(access_token)
    assert_response :forbidden
    assert_equal -32003, response.parsed_body.dig("error", "code")
    assert_not Post.exists?(title: "OAuth read draft")
  end

  test "revoked oauth token is rejected with 401" do
    access_token = obtain_oauth_token("read")
    Doorkeeper::AccessToken.by_token(access_token).revoke

    post mcp_path, params: { jsonrpc: "2.0", id: 1, method: "tools/list" }.to_json,
      headers: mcp_headers(access_token)
    assert_response :unauthorized
    assert_equal -32001, response.parsed_body.dig("error", "code")
  end

  test "expired oauth token is rejected with 401" do
    access_token = obtain_oauth_token("read")
    Doorkeeper::AccessToken.by_token(access_token).update!(created_at: 3.hours.ago)

    post mcp_path, params: { jsonrpc: "2.0", id: 1, method: "tools/list" }.to_json,
      headers: mcp_headers(access_token)
    assert_response :unauthorized
    assert_equal -32001, response.parsed_body.dig("error", "code")
  end

  test "confidential client exchanges authorization code with client_secret using PKCE" do
    confidential_app = Doorkeeper::Application.create!(
      name: "Confidential Client",
      redirect_uri: "https://confidential.example.com/callback",
      scopes: "read write",
      confidential: true
    )
    post admin_login_path, params: { email: @admin.email, password: "password123" }
    assert_redirected_to admin_posts_path

    verifier, challenge = pkce_pair
    post oauth_authorization_path(authorization_params(challenge, confidential_app))
    assert_response :redirect
    location = URI.parse(response.headers["Location"])
    assert_equal "confidential.example.com", location.host
    code = URI.decode_www_form(location.query || "").to_h["code"]
    assert code.present?

    assert_difference("Doorkeeper::AccessToken.count", 1) do
      post oauth_token_path, params: {
        grant_type: "authorization_code",
        code: code,
        redirect_uri: confidential_app.redirect_uri,
        client_id: confidential_app.uid,
        client_secret: confidential_app.secret,
        code_verifier: verifier
      }
    end
    assert_response :success
    payload = response.parsed_body
    assert payload["access_token"].present?
    assert payload["refresh_token"].present?
  end

  test "confidential client token exchange without or with wrong secret is rejected" do
    confidential_app = Doorkeeper::Application.create!(
      name: "Confidential Client",
      redirect_uri: "https://confidential.example.com/callback",
      scopes: "read write",
      confidential: true
    )
    post admin_login_path, params: { email: @admin.email, password: "password123" }
    assert_redirected_to admin_posts_path

    verifier, challenge = pkce_pair
    post oauth_authorization_path(authorization_params(challenge, confidential_app))
    assert_response :redirect
    code_without_secret = URI.decode_www_form(URI.parse(response.headers["Location"]).query || "").to_h["code"]
    assert code_without_secret.present?

    assert_no_difference("Doorkeeper::AccessToken.count") do
      post oauth_token_path, params: {
        grant_type: "authorization_code",
        code: code_without_secret,
        redirect_uri: confidential_app.redirect_uri,
        client_id: confidential_app.uid,
        code_verifier: verifier
      }
    end
    assert_response :unauthorized

    verifier2, challenge2 = pkce_pair
    post oauth_authorization_path(authorization_params(challenge2, confidential_app))
    assert_response :redirect
    code_wrong_secret = URI.decode_www_form(URI.parse(response.headers["Location"]).query || "").to_h["code"]
    assert code_wrong_secret.present?

    assert_no_difference("Doorkeeper::AccessToken.count") do
      post oauth_token_path, params: {
        grant_type: "authorization_code",
        code: code_wrong_secret,
        redirect_uri: confidential_app.redirect_uri,
        client_id: confidential_app.uid,
        client_secret: "wrong-secret",
        code_verifier: verifier2
      }
    end
    assert_response :unauthorized
  end

  test "confidential client refreshes access token with client_secret" do
    confidential_app = Doorkeeper::Application.create!(
      name: "Confidential Client",
      redirect_uri: "https://confidential.example.com/callback",
      scopes: "read write",
      confidential: true
    )
    post admin_login_path, params: { email: @admin.email, password: "password123" }
    assert_redirected_to admin_posts_path

    verifier, challenge = pkce_pair
    post oauth_authorization_path(authorization_params(challenge, confidential_app))
    assert_response :redirect
    code = URI.decode_www_form(URI.parse(response.headers["Location"]).query || "").to_h["code"]
    assert code.present?

    post oauth_token_path, params: {
      grant_type: "authorization_code",
      code: code,
      redirect_uri: confidential_app.redirect_uri,
      client_id: confidential_app.uid,
      client_secret: confidential_app.secret,
      code_verifier: verifier
    }
    assert_response :success
    refresh_token = response.parsed_body["refresh_token"]
    assert refresh_token.present?

    post oauth_token_path, params: {
      grant_type: "refresh_token",
      refresh_token: refresh_token,
      client_id: confidential_app.uid,
      client_secret: confidential_app.secret
    }
    assert_response :success
    assert response.parsed_body["access_token"].present?
  end

  test "login via stored return_to resumes OAuth authorization with PKCE params" do
    _verifier, challenge = pkce_pair
    auth_params = authorization_params(challenge)

    get oauth_authorization_path(auth_params)
    assert_redirected_to admin_login_path
    stored = session[:return_to]
    assert_match(%r{\A/oauth/authorize}, stored)
    assert_includes stored, "code_challenge="
    assert_includes stored, "state=test-state"

    post admin_login_path, params: { email: @admin.email, password: "password123" }
    assert_response :redirect
    location = response.headers["Location"]
    assert_includes location, "/oauth/authorize"
    assert_includes location, "code_challenge="
    assert_includes location, "state=test-state"
  end

  test "external return_to falls back to admin posts" do
    get admin_login_path
    assert_response :success
    session[:return_to] = "//evil.com/phish"

    post admin_login_path, params: { email: @admin.email, password: "password123" }
    assert_redirected_to admin_posts_path
  end

  test "successful login rotates session id to prevent fixation" do
    _verifier, challenge = pkce_pair
    get oauth_authorization_path(authorization_params(challenge))
    assert_redirected_to admin_login_path
    old_session_id = session.id.to_s
    assert old_session_id.present?

    post admin_login_path, params: { email: @admin.email, password: "password123" }
    assert_response :redirect
    assert_includes response.headers["Location"], "/oauth/authorize"
    new_session_id = session.id.to_s

    assert new_session_id.present?
    assert_not_equal old_session_id, new_session_id
  end

  private

  def authorization_params(challenge, application = @application)
    params = {
      client_id: application.uid,
      redirect_uri: application.redirect_uri,
      response_type: "code",
      scope: "read",
      state: "test-state"
    }
    if challenge
      params[:code_challenge] = challenge
      params[:code_challenge_method] = "S256"
    end
    params
  end

  def pkce_pair
    verifier = SecureRandom.urlsafe_base64(32)
    challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)
    [ verifier, challenge ]
  end

  def obtain_oauth_token(scope)
    post admin_login_path, params: { email: @admin.email, password: "password123" }
    assert_redirected_to admin_posts_path

    verifier, challenge = pkce_pair
    post oauth_authorization_path(authorization_params(challenge).merge(scope: scope))
    assert_response :redirect
    code = URI.decode_www_form(URI.parse(response.headers["Location"]).query || "").to_h["code"]
    assert code.present?

    post oauth_token_path, params: {
      grant_type: "authorization_code",
      code: code,
      redirect_uri: @application.redirect_uri,
      client_id: @application.uid,
      code_verifier: verifier
    }
    assert_response :success
    response.parsed_body.fetch("access_token")
  end

  def mcp_headers(token)
    {
      "Authorization" => "Bearer #{token}",
      "CONTENT_TYPE" => "application/json",
      "ACCEPT" => "application/json, text/event-stream"
    }
  end
end
