# typed: true

class McpController < ActionController::API
  TOOL_SCOPES = {
    "search_posts" => :read,
    "get_post" => :read,
    "create_draft" => :write,
    "update_draft" => :write
  }.freeze

  before_action :authenticate_api_key!
  after_action :record_api_key_usage

  def create
    payload = parse_json_body
    return deny_write_tool_for_read_key(payload) if read_key_calling_write_tool?(payload)

    server = MCP::Server.new(
      name: "tech-notes",
      title: "Hiroe Tech Notes",
      version: "1.0.0",
      instructions: "Search and reference published blog posts. Create and update drafts owned by the API key owner.",
      tools: [ SearchPostsTool, GetPostTool, CreateDraftTool, UpdateDraftTool ],
      server_context: { api_key: @api_key },
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

  def authenticate_api_key!
    @api_key = ApiKey.find_active_by_token(bearer_token)
    return if @api_key

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

  def read_key_calling_write_tool?(payload)
    return false unless payload.is_a?(Hash)
    return false unless payload["method"] == "tools/call"

    required_scope = TOOL_SCOPES[payload.dig("params", "name")]
    return false unless required_scope

    required_scope == :write && !@api_key.write?
  end

  def deny_write_tool_for_read_key(payload)
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
    tool_name = payload.is_a?(Hash) ? payload.dig("params", "name") : nil
    message = +"[mcp] method=#{rpc_method || "-"}"
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
    tool_name.to_s.gsub(/[^a-zA-Z0-9_\-.]/, "?")
  end
end
