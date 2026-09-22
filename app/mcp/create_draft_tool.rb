# typed: true

class CreateDraftTool < MCP::Tool
  tool_name "create_draft"
  description "Create a new draft post. The post is always saved as a draft and is never published."
  input_schema(
    properties: {
      title: { type: "string" },
      body: { type: "string" },
      slug: { type: "string" },
      tags: { type: "array", items: { type: "string" } }
    },
    required: [ "title", "body" ],
  )

  class << self
    def call(title: nil, body: nil, slug: nil, tags: nil, server_context: nil)
      api_key = server_context && server_context[:api_key]
      return error_response("Missing API key context.") unless api_key
      return error_response("Forbidden: this tool requires write scope.") unless api_key.write?

      post = Post.new(title: title.to_s, body: body.to_s, admin_user: api_key.admin_user, status: :draft)

      begin
        Post.transaction do
          post.slug = slug.to_s if slug.present?
          unless tags.nil?
            tag_list = Array(tags).flatten.map { |t| t.to_s.strip }.reject(&:blank?).uniq
            post.tag_names = tag_list.join(", ")
          end
          post.save!
        end
      rescue ActiveRecord::RecordInvalid
        return error_response(validation_summary(post))
      end

      MCP::Tool::Response.new([ { type: "text", text: JSON.generate(
        id: post.id,
        slug: post.slug,
        title: post.title,
        status: post.status,
      ) } ])
    end

    private

    def validation_summary(post)
      I18n.with_locale(:en) { post.errors.full_messages.join("; ") }
    end

    def error_response(text)
      MCP::Tool::Response.new([ { type: "text", text: text } ], error: true)
    end
  end
end
