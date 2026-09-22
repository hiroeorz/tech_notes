require "test_helper"

class McpTest < ActionDispatch::IntegrationTest
  setup do
    @category = Category.create!(name: "AWS", name_en: "AWS", slug: "aws", icon_key: "aws", position: 1)
    @owner = AdminUser.create!(
      email: "key-owner@example.com",
      password_salt: "salt",
      password_digest: AdminUser.digest_password("password123", "salt")
    )
    @other_admin = AdminUser.create!(
      email: "other-admin@example.com",
      password_salt: "other-salt",
      password_digest: AdminUser.digest_password("password123", "other-salt")
    )

    @read_key, @read_token = ApiKey.issue(admin_user: @owner, name: "MCP read", scope: :read)
    @write_key, @write_token = ApiKey.issue(admin_user: @owner, name: "MCP write", scope: :write)

    @published_post = Post.create!(
      admin_user: @owner,
      title: "Terraform remote state notes",
      slug: "terraform-remote-state",
      body: "Terraform remote state and locking notes.",
      status: :published,
      published_at: 3.days.ago
    )
    @draft_post = Post.create!(
      admin_user: @owner,
      title: "Draft search hidden",
      slug: "draft-search-hidden",
      body: "Draft body with terraform keyword.",
      status: :draft
    )
    @reviewing_post = Post.create!(
      admin_user: @owner,
      title: "Reviewing post",
      slug: "reviewing-post",
      body: "Reviewing body with terraform keyword.",
      status: :reviewing
    )
    @future_post = Post.create!(
      admin_user: @owner,
      title: "Future published post",
      slug: "future-published-post",
      body: "Future body with terraform keyword.",
      status: :published,
      published_at: 1.day.from_now
    )
    @other_admin_draft = Post.create!(
      admin_user: @other_admin,
      title: "Other admin draft",
      slug: "other-admin-draft",
      body: "Owned by another admin."
    )
  end

  test "missing api key is rejected with 401" do
    post mcp_path, params: tools_list_request.to_json,
      headers: rpc_headers(nil)

    assert_response :unauthorized
    assert_equal "2.0", response.parsed_body.fetch("jsonrpc")
    assert_nil response.parsed_body.fetch("id")
    assert_equal -32001, response.parsed_body.dig("error", "code")
    assert_equal "Unauthorized: missing, invalid, or revoked API key.", response.parsed_body.dig("error", "message")
  end

  test "invalid api key is rejected with 401" do
    rpc_post("tn_wrong_token", tools_list_request)

    assert_response :unauthorized
    assert_equal -32001, response.parsed_body.dig("error", "code")
  end

  test "revoked api key is rejected with 401 and usage is not recorded" do
    @read_key.revoke!
    rpc_post(@read_token, tools_list_request)

    assert_response :unauthorized
    assert_equal -32001, response.parsed_body.dig("error", "code")
    assert_nil @read_key.reload.last_used_at
  end

  test "read scope key cannot call create_draft or update_draft" do
    rpc_post(@read_token, tools_call_request("create_draft", title: "Read key draft", body: "Body."))

    assert_response :forbidden
    error = response.parsed_body.fetch("error")
    assert_equal -32003, error.fetch("code")
    assert_equal "Forbidden: tool 'create_draft' requires write scope.", error.fetch("message")
    assert_not Post.exists?(title: "Read key draft")

    rpc_post(@read_token, tools_call_request("update_draft", id: @draft_post.id, title: "Read key update"))

    assert_response :forbidden
    assert_equal "Forbidden: tool 'update_draft' requires write scope.", response.parsed_body.dig("error", "message")
    assert_not_equal "Read key update", @draft_post.reload.title
  end

  test "read scope key can list tools and call read tools" do
    rpc_post(@read_token, tools_list_request)

    assert_response :success

    rpc_post(@read_token, tools_call_request("search_posts", query: "terraform"))

    assert_response :success
    assert_includes tool_payload.map { it.fetch("slug") }, "terraform-remote-state"
  end

  test "write scope key can search, get, create and update drafts" do
    rpc_post(@write_token, tools_call_request("search_posts", query: "terraform"))

    assert_response :success

    rpc_post(@write_token, tools_call_request("get_post", slug: @published_post.slug))

    assert_response :success

    rpc_post(@write_token, tools_call_request("create_draft", title: "Write key draft", body: "Body."))

    assert_response :success
    draft_id = tool_payload.fetch("id")

    rpc_post(@write_token, tools_call_request("update_draft", id: draft_id, title: "Updated by write key"))

    assert_response :success
    assert_equal "Updated by write key", tool_payload.fetch("title")
  end

  test "tools/list exposes only the four blog tools" do
    rpc_post(@write_token, tools_list_request)

    assert_response :success
    names = response.parsed_body.dig("result", "tools").map { it.fetch("name") }

    assert_equal %w[create_draft get_post search_posts update_draft], names.sort
    %w[delete_post delete_draft publish_post unpublish_post].each do |forbidden_tool|
      assert_not_includes names, forbidden_tool
    end
    refute_plaintext_tokens_in_response
  end

  test "search_posts returns only publicly visible posts" do
    rpc_post(@write_token, tools_call_request("search_posts", query: "terraform"))

    assert_response :success
    slugs = tool_payload.map { it.fetch("slug") }

    assert_includes slugs, "terraform-remote-state"
    assert_not_includes slugs, "draft-search-hidden"
    assert_not_includes slugs, "reviewing-post"
    assert_not_includes slugs, "future-published-post"
    refute_plaintext_tokens_in_response
  end

  test "search_posts narrows by all specified tags" do
    terraform_tag = Tag.create!(name: "Terraform", slug: "terraform")
    aws_tag = Tag.create!(name: "AWS", slug: "aws")
    terraform_only = Post.create!(
      admin_user: @owner,
      title: "Terraform only",
      slug: "terraform-only",
      body: "Terraform only.",
      status: :published,
      published_at: 2.days.ago
    )
    terraform_only.tags << terraform_tag
    terraform_and_aws = Post.create!(
      admin_user: @owner,
      title: "Terraform and AWS",
      slug: "terraform-aws",
      body: "Terraform with AWS.",
      status: :published,
      published_at: 1.day.ago
    )
    terraform_and_aws.tags << terraform_tag
    terraform_and_aws.tags << aws_tag

    rpc_post(@write_token, tools_call_request("search_posts", query: "terraform", tags: [ "Terraform", "AWS" ]))

    assert_response :success
    assert_equal [ "terraform-aws" ], tool_payload.map { it.fetch("slug") }

    rpc_post(@write_token, tools_call_request("search_posts", query: "terraform", tags: [ "Terraform", "Missing" ]))

    assert_response :success
    assert_equal [], tool_payload
  end

  test "search_posts clamps limit between 1 and 50" do
    52.times do |index|
      Post.create!(
        admin_user: @owner,
        title: "Clamp target #{index}",
        slug: "clamp-target-#{index}",
        body: "Clamp target body #{index}.",
        status: :published,
        published_at: index.days.ago
      )
    end

    rpc_post(@write_token, tools_call_request("search_posts", query: "clamp target", limit: 3))

    assert_response :success
    assert_equal 3, tool_payload.length

    rpc_post(@write_token, tools_call_request("search_posts", query: "clamp target", limit: 60))

    assert_response :success
    assert_equal 50, tool_payload.length

    rpc_post(@write_token, tools_call_request("search_posts", query: "clamp target", limit: 0))

    assert_response :success
    assert_equal 1, tool_payload.length

    rpc_post(@write_token, tools_call_request("search_posts", query: "clamp target"))

    assert_response :success
    assert_equal 10, tool_payload.length
  end

  test "get_post returns the full markdown content by slug or id" do
    rpc_post(@write_token, tools_call_request("get_post", slug: @published_post.slug))

    assert_response :success
    payload = tool_payload

    assert_equal @published_post.id, payload.fetch("id")
    assert_equal "terraform-remote-state", payload.fetch("slug")
    assert_equal "Terraform remote state notes", payload.fetch("title")
    assert_equal "Terraform remote state and locking notes.", payload.fetch("body")

    rpc_post(@write_token, tools_call_request("get_post", id: @published_post.id))

    assert_response :success
    assert_equal @published_post.id, tool_payload.fetch("id")
  end

  test "get_post rejects draft posts" do
    rpc_post(@write_token, tools_call_request("get_post", slug: @draft_post.slug))

    assert_response :success
    assert_equal true, response.parsed_body.dig("result", "isError")
    assert_equal "Post not found.", tool_text
  end

  test "get_post rejects ambiguous and missing locators" do
    rpc_post(@write_token, tools_call_request("get_post", slug: @published_post.slug, id: @published_post.id))

    assert_response :success
    assert_equal "Provide either 'slug' or 'id', not both.", tool_text
    assert_equal true, response.parsed_body.dig("result", "isError")

    rpc_post(@write_token, tools_call_request("get_post"))

    assert_response :success
    assert_equal "Provide either 'slug' or 'id'.", tool_text
    assert_equal true, response.parsed_body.dig("result", "isError")
  end

  test "create_draft always saves a draft owned by the api key owner" do
    rpc_post(@write_token, tools_call_request("create_draft", title: "MCP created draft", body: "Hello MCP world"))

    assert_response :success
    result = tool_payload

    assert_equal "draft", result.fetch("status")
    post = Post.find(result.fetch("id"))

    assert_equal @owner.id, post.admin_user_id
    assert_not_equal @other_admin.id, post.admin_user_id
    assert post.draft?
    assert_equal "mcp-created-draft", post.slug
    assert_equal "Hello MCP world", post.excerpt
    refute_plaintext_tokens_in_response
  end

  test "create_draft accepts explicit slug and tags" do
    rpc_post(@write_token, tools_call_request(
      "create_draft",
      title: "Tagged draft",
      body: "Body text.",
      slug: "custom-draft-slug",
      tags: [ "Terraform", "AWS" ]
    ))

    assert_response :success
    result = tool_payload

    assert_equal "custom-draft-slug", result.fetch("slug")
    post = Post.find(result.fetch("id"))

    assert_equal "custom-draft-slug", post.slug
    assert_equal %w[AWS Terraform], post.tags.map(&:name).sort
  end

  test "create_draft returns a validation summary for duplicate slug" do
    rpc_post(@write_token, tools_call_request(
      "create_draft",
      title: "Duplicate slug draft",
      body: "Body text.",
      slug: @published_post.slug
    ))

    assert_response :success
    assert_equal true, response.parsed_body.dig("result", "isError")
    assert_includes tool_text, "Slug has already been taken"
    assert_not Post.exists?(title: "Duplicate slug draft")
  end

  test "update_draft updates title, body and tags of an owned draft" do
    rpc_post(@write_token, tools_call_request(
      "update_draft",
      id: @draft_post.id,
      title: "Updated draft title",
      body: "Updated draft body.",
      tags: [ "AWS" ]
    ))

    assert_response :success
    result = tool_payload

    assert_equal "Updated draft title", result.fetch("title")
    assert_equal "draft", result.fetch("status")
    @draft_post.reload

    assert_equal "Updated draft body.", @draft_post.body
    assert_equal [ "AWS" ], @draft_post.tags.map(&:name)
    assert_nil @draft_post.published_at
  end

  test "update_draft can rename slug when located by id" do
    rpc_post(@write_token, tools_call_request("update_draft", id: @draft_post.id, slug: "renamed-draft-slug"))

    assert_response :success
    assert_equal "renamed-draft-slug", tool_payload.fetch("slug")
    assert_equal "renamed-draft-slug", @draft_post.reload.slug
  end

  test "update_draft does not change slug when located by slug" do
    rpc_post(@write_token, tools_call_request("update_draft", slug: "draft-search-hidden", title: "Retitled draft"))

    assert_response :success
    assert_equal "Retitled draft", tool_payload.fetch("title")
    assert_equal "draft-search-hidden", @draft_post.reload.slug
  end

  test "update_draft refuses published and reviewing posts" do
    rpc_post(@write_token, tools_call_request("update_draft", id: @published_post.id, title: "Hacked title"))

    assert_response :success
    assert_equal true, response.parsed_body.dig("result", "isError")
    assert_equal "Only draft posts can be updated.", tool_text
    assert_equal "Terraform remote state notes", @published_post.reload.title

    rpc_post(@write_token, tools_call_request("update_draft", id: @reviewing_post.id, title: "Hacked review"))

    assert_response :success
    assert_equal "Only draft posts can be updated.", tool_text
    assert_equal "Reviewing post", @reviewing_post.reload.title
  end

  test "update_draft cannot update drafts owned by another admin" do
    rpc_post(@write_token, tools_call_request("update_draft", id: @other_admin_draft.id, title: "Hacked other draft"))

    assert_response :success
    assert_equal true, response.parsed_body.dig("result", "isError")
    assert_equal "Post not found.", tool_text
    assert_equal "Other admin draft", @other_admin_draft.reload.title
  end

  test "update_draft refuses to change status or published_at" do
    rpc_post(@write_token, tools_call_request(
      "update_draft",
      id: @draft_post.id,
      title: "Still a draft",
      body: "Still a draft body."
    ))

    assert_response :success
    @draft_post.reload

    assert_equal "draft", @draft_post.status
    assert_nil @draft_post.published_at
  end

  test "malformed json body returns a parse error instead of a server error" do
    post mcp_path, params: "{ this is not json", headers: rpc_headers(@write_token)

    assert_response :bad_request
    assert_equal -32700, response.parsed_body.dig("error", "code")
  end

  test "unknown json rpc method returns method not found" do
    rpc_post(@write_token, { jsonrpc: "2.0", id: 7, method: "articles/destroy" })

    assert_equal -32601, response.parsed_body.dig("error", "code")
  end

  test "get_post with unknown slug returns a tool error" do
    rpc_post(@write_token, tools_call_request("get_post", slug: "missing-slug"))

    assert_response :success
    assert_equal true, response.parsed_body.dig("result", "isError")
    assert_equal "Post not found.", tool_text
  end

  test "successful requests record api key usage" do
    assert_nil @write_key.last_used_at

    rpc_post(@write_token, tools_list_request)

    assert_response :success
    assert_not_nil @write_key.reload.last_used_at
  end

  test "settings page shows api keys section without plaintext tokens" do
    sign_in_admin(@owner)

    get admin_settings_path

    assert_response :success
    assert_includes response.body, I18n.t("admin.settings.show.api_keys_section")
    assert_includes response.body, @read_key.key_prefix
    assert_includes response.body, I18n.t("admin.api_keys.status_active")
    refute_plaintext_tokens_in_response
  end

  test "issuing a key from admin ui shows plaintext once and keeps it out of flash, session and later pages" do
    sign_in_admin(@owner)

    assert_difference "ApiKey.count", 1 do
      post admin_api_keys_path, params: { name: "Claude Desktop", scope: "read" }
    end

    assert_response :success
    token = response.body[/tn_[A-Za-z0-9]+/]
    assert_not_nil token
    assert_includes response.body, I18n.t("admin.api_keys.created_warning")

    key = ApiKey.order(:id).last
    assert_equal @owner.id, key.admin_user_id
    assert_equal "read", key.scope
    assert_equal key.key_prefix, token[0, 8]
    assert_equal Digest::SHA256.hexdigest(token), key.key_digest

    assert_not_includes flash.to_hash.values.compact.map(&:to_s).join(" "), token
    assert_not_includes session.to_hash.inspect, token

    get admin_settings_path

    assert_response :success
    assert_includes response.body, key.key_prefix
    assert_not_includes response.body, token
  end

  test "key issued from admin ui can immediately call mcp write tools" do
    sign_in_admin(@owner)

    post admin_api_keys_path, params: { name: "MCP Inspector", scope: "write" }

    assert_response :success
    token = response.body[/tn_[A-Za-z0-9]+/]

    rpc_post(token, tools_call_request("create_draft", title: "UI issued draft", body: "Body."))

    assert_response :success
    assert_equal "draft", tool_payload.fetch("status")
  end

  test "revoking a key from admin ui updates the list and blocks mcp access" do
    sign_in_admin(@owner)

    patch revoke_admin_api_key_path(@read_key)

    assert_redirected_to admin_settings_path
    assert_not_nil @read_key.reload.revoked_at

    follow_redirect!

    assert_response :success
    assert_includes response.body, I18n.t("admin.api_keys.status_revoked")

    rpc_post(@read_token, tools_list_request)

    assert_response :unauthorized
    assert_equal -32001, response.parsed_body.dig("error", "code")
  end

  test "admin cannot revoke another admin's api key" do
    sign_in_admin(@other_admin)

    assert_no_difference "ApiKey.count" do
      patch revoke_admin_api_key_path(@read_key)
    end

    assert_response :not_found
    assert_nil @read_key.reload.revoked_at
  end

  test "issuing a key without name redirects with alert and creates nothing" do
    sign_in_admin(@owner)

    assert_no_difference "ApiKey.count" do
      post admin_api_keys_path, params: { name: "", scope: "read" }
    end

    assert_redirected_to admin_settings_path
    assert_equal I18n.t("flash.admin.api_keys.create_failed"), flash[:alert]
  end

  test "issuing a key with invalid scope redirects with alert and creates nothing" do
    sign_in_admin(@owner)

    assert_no_difference "ApiKey.count" do
      post admin_api_keys_path, params: { name: "Bad scope", scope: "admin" }
    end

    assert_redirected_to admin_settings_path
    assert_equal I18n.t("flash.admin.api_keys.create_failed"), flash[:alert]
  end

  test "write tools enforce write scope at tool layer" do
    create_response = CreateDraftTool.call(
      title: "Tool layer draft", body: "Body.", server_context: { api_key: @read_key }
    )

    assert create_response.error?
    assert_equal "Forbidden: this tool requires write scope.", create_response.content.first[:text]
    assert_not Post.exists?(title: "Tool layer draft")

    update_response = UpdateDraftTool.call(
      id: @draft_post.id, title: "Hacked at tool layer", server_context: { api_key: @read_key }
    )

    assert update_response.error?
    assert_equal "Forbidden: this tool requires write scope.", update_response.content.first[:text]
    assert_not_equal "Hacked at tool layer", @draft_post.reload.title
  end

  test "create_draft normalizes string tags to a single tag" do
    response = CreateDraftTool.call(
      title: "String tags draft", body: "Body.", tags: "Terraform",
      server_context: { api_key: @write_key }
    )

    assert_not response.error?
    post = Post.find(JSON.parse(response.content.first[:text]).fetch("id"))

    assert_equal [ "Terraform" ], post.tags.map(&:name)
  end

  test "update_draft keeps existing tags when tags param is omitted" do
    @draft_post.tags << Tag.create!(name: "KeepMe", slug: "keep-me")

    response = UpdateDraftTool.call(
      id: @draft_post.id, title: "Retitled without tags",
      server_context: { api_key: @write_key }
    )

    assert_not response.error?
    assert_equal [ "KeepMe" ], @draft_post.reload.tags.map(&:name)
  end

  test "search_posts with non-numeric or array limit still responds 200" do
    rpc_post(@write_token, tools_call_request("search_posts", query: "terraform", limit: "abc"))

    assert_response :success

    rpc_post(@write_token, tools_call_request("search_posts", query: "terraform", limit: [ 5 ]))

    assert_response :success

    assert_nothing_raised do
      SearchPostsTool.call(query: "terraform", limit: "abc")
      SearchPostsTool.call(query: "terraform", limit: [ 5 ])
    end
  end

  test "notification without id is acknowledged without server error" do
    post mcp_path, params: { jsonrpc: "2.0", method: "notifications/initialized" }.to_json,
      headers: rpc_headers(@write_token)

    assert_equal 202, response.status
  end

  test "delete mcp does not raise server error" do
    delete mcp_path, headers: rpc_headers(@write_token)

    assert_equal 200, response.status
  end

  test "failed requests do not update last_used_at" do
    @read_key.update_column(:last_used_at, nil)
    @write_key.update_column(:last_used_at, nil)

    rpc_post(@read_token, tools_call_request("create_draft", title: "No usage", body: "Body."))

    assert_response :forbidden
    assert_nil @read_key.reload.last_used_at

    post mcp_path, params: "{ this is not json", headers: rpc_headers(@write_token)

    assert_response :bad_request
    assert_nil @write_key.reload.last_used_at
  end

  test "issuing a colliding key redirects with alert and creates nothing" do
    sign_in_admin(@owner)

    original_base58 = SecureRandom.method(:base58)
    SecureRandom.define_singleton_method(:base58) { |*| "x" * 32 }
    begin
      assert_difference "ApiKey.count", 1 do
        post admin_api_keys_path, params: { name: "First collision", scope: "read" }
      end

      assert_response :success

      assert_no_difference "ApiKey.count" do
        post admin_api_keys_path, params: { name: "Second collision", scope: "read" }
      end

      assert_redirected_to admin_settings_path
      assert_equal I18n.t("flash.admin.api_keys.create_failed"), flash[:alert]
    ensure
      SecureRandom.define_singleton_method(:base58, original_base58)
    end
  end

  test "get_post and update_draft reject non-numeric id with tool error" do
    get_response = GetPostTool.call(id: "abc")

    assert get_response.error?
    assert_equal "Invalid 'id': must be an integer.", get_response.content.first[:text]

    update_response = UpdateDraftTool.call(
      id: "abc", title: "Nope", server_context: { api_key: @write_key }
    )

    assert update_response.error?
    assert_equal "Invalid 'id': must be an integer.", update_response.content.first[:text]

    rpc_post(@write_token, tools_call_request("get_post", id: "abc"))

    assert_response :success
  end

  test "tool names are sanitized for logging" do
    sanitize = ->(name) { McpController.new.send(:sanitized_tool_name_for_log, name) }

    assert_equal "create_draft", sanitize.call("create_draft")
    assert_equal "evil?tool??name", sanitize.call("evil tool\n?name")
  end

  test "tools/call with non-object params returns transport error without server error" do
    rpc_post(@write_token, { jsonrpc: "2.0", id: 1, method: "tools/call", params: [] })

    assert_response :success
    assert_equal -32603, response.parsed_body.dig("error", "code")

    rpc_post(@write_token, { jsonrpc: "2.0", id: 1, method: "tools/call", params: "oops" })

    assert_response :success
    assert_equal -32602, response.parsed_body.dig("error", "code")
  end

  private

  def sign_in_admin(admin)
    post admin_login_path, params: { email: admin.email, password: "password123" }
    assert_redirected_to admin_posts_path
  end

  def rpc_headers(token)
    {
      "Authorization" => "Bearer #{token}",
      "CONTENT_TYPE" => "application/json",
      "ACCEPT" => "application/json, text/event-stream"
    }
  end

  def rpc_post(token, payload)
    post mcp_path, params: payload.to_json, headers: rpc_headers(token)
  end

  def tools_list_request
    { jsonrpc: "2.0", id: 1, method: "tools/list" }
  end

  def tools_call_request(tool_name, arguments = {})
    { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: tool_name, arguments: arguments } }
  end

  def tool_text
    response.parsed_body.dig("result", "content", 0, "text")
  end

  def tool_payload
    JSON.parse(tool_text)
  end

  def refute_plaintext_tokens_in_response
    [ @read_token, @write_token ].each do |token|
      assert_not_includes response.body, token
    end
  end
end
