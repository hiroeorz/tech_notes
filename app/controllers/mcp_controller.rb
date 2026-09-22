# typed: true

class McpController < ActionController::API
  TOOL_SCOPES = {
    "search_posts" => :read,
    "get_post" => :read,
    "create_draft" => :write,
    "update_draft" => :write
  }.freeze

  before_action :authenticate_credential!
  after_action :record_api_key_usage

  def create
    payload = parse_json_body
    return deny_write_tool_for_read_scope(payload) if read_scope_calling_write_tool?(payload)

    server = MCP::Server.new(
      name: "tech-notes",
      title: "Hiroe Tech Notes",
      version: "1.0.0",
      instructions: "Search and reference published blog posts. Create and update drafts owned by the API key owner.",
      tools: [ SearchPostsTool, GetPostTool, CreateDraftTool, UpdateDraftTool ],
      server_context: { owner: @credential_owner, scope: @credential_scope },
    )
    transport = MCP::Server::Transports::StreamableHTTPTransport.new(
      server,
      stateless: true,
      enable_json_response: true,
      serve_subscriptions_listen: false,
      allowed_hosts: [ request.host ],
    )

    status, headers, body = transport.handle_request(request)
    observe_request(status, payload)
    respond_with_transport_result(status, headers, body)
  end

  private

  def authenticate_credential!
    token = bearer_token
    api_key = ApiKey.find_active_by_token(token)
    if api_key
      @api_key = api_key
      @credential_owner = api_key.admin_user
      @credential_scope = api_key.scope
      return
    end

    oauth_token = token.present? ? Doorkeeper::AccessToken.by_token(token) : nil
    if oauth_token&.accessible?
      owner = AdminUser.find_by(id: oauth_token.resource_owner_id)
      if owner
        @credential_owner = owner
        @credential_scope = oauth_token.includes_scope?("write") ? "write" : "read"
        return
      end
    end

    render json: {
      jsonrpc: "2.0",
      id: nil,
      error: {
        code: -32001,
        message: "Unauthorized: missing, invalid, or revoked API key."
      }
    }, status: :unauthorized
  end

  def bearer_token
    match = request.headers["Authorization"].to_s.match(/\ABearer\s+(.+)\z/i)
    match && match[1].strip.presence
  end

  def parse_json_body
    JSON.parse(request.raw_post)
  rescue JSON::ParserError, TypeError
    nil
  end

  def read_scope_calling_write_tool?(payload)
    return false unless payload.is_a?(Hash)
    return false unless payload["method"] == "tools/call"

    params = payload["params"]
    return false unless params.is_a?(Hash)

    required_scope = TOOL_SCOPES[params["name"]]
    return false unless required_scope

    required_scope == :write && @credential_scope != "write"
  end

  def deny_write_tool_for_read_scope(payload)
    tool_name = payload.dig("params", "name")
    observe_request(403, payload)
    render json: {
      jsonrpc: "2.0",
      id: payload["id"],
      error: {
        code: -32003,
        message: "Forbidden: tool '#{tool_name}' requires write scope."
      }
    }, status: :forbidden
  end

  def observe_request(status, payload)
    rpc_method = payload.is_a?(Hash) ? payload["method"] : nil
    params = payload.is_a?(Hash) ? payload["params"] : nil
    tool_name = params.is_a?(Hash) ? params["name"] : nil
    message = +"[mcp] method=#{sanitized_method_for_log(rpc_method || "-")}"
    message << " tool=#{sanitized_tool_name_for_log(tool_name)}" if tool_name
    message << " status=#{status}"
    Rails.logger.info(message)
  end

  def respond_with_transport_result(status, headers, body)
    payload = body.first
    if payload.is_a?(String) && payload.present?
      headers.each { |name, value| response.headers[name] = value }
      render json: payload, status: status
    else
      headers.each { |name, value| response.headers[name] = value }
      head status
    end
  end

  def record_api_key_usage
    @api_key.record_usage! if @api_key && response.status < 400
  end

  def sanitized_tool_name_for_log(tool_name)
    sanitized_value_for_log(tool_name)
  end

  def sanitized_method_for_log(rpc_method)
    sanitized_value_for_log(rpc_method)
  end

  def sanitized_value_for_log(value)
    value.to_s.gsub(/[^a-zA-Z0-9_\-.]/, "?").truncate(128)
  end
end
