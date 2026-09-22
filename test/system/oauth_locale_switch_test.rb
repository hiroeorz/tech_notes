require "application_system_test_case"
require "base64"
require "digest"
require "securerandom"
require "uri"

class OauthLocaleSwitchTest < ApplicationSystemTestCase
  setup do
    AdminUser.create!(
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

    visit admin_login_path
    fill_in "Email", with: "admin@example.com"
    fill_in "Password", with: "password123"
    click_on "Log in"
    assert_current_path admin_posts_path
  end

  test "switching language on consent screen keeps authorization query and renders Japanese" do
    verifier = SecureRandom.urlsafe_base64(32)
    challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)
    visit oauth_authorization_path(
      client_id: @application.uid,
      redirect_uri: @application.redirect_uri,
      response_type: "code",
      scope: "read",
      state: "test-state",
      code_challenge: challenge,
      code_challenge_method: "S256"
    )
    assert_text "is requesting access"

    find("select.locale-select").find("option[value='ja']").select_option

    assert_text "アクセス許可"
    assert_text "があなたのアカウントへのアクセスを求めています"

    current_uri = URI.parse(page.current_url)
    assert_equal "/oauth/authorize", current_uri.path
    query = URI.decode_www_form(current_uri.query || "").to_h
    assert query["client_id"].present?
    assert query["code_challenge"].present?
    assert_equal "test-state", query["state"]
  end
end
