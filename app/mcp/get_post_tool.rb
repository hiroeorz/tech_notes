# typed: true

class GetPostTool < MCP::Tool
  tool_name "get_post"
  description "Get the full content of a published post by slug or id. Body is returned as Markdown."
  input_schema(
    properties: {
      slug: { type: "string" },
      id: { type: "number" }
    },
  )

  class << self
    def call(slug: nil, id: nil, server_context: nil)
      return error_response("Provide either 'slug' or 'id'.") if slug.blank? && id.blank?
      return error_response("Provide either 'slug' or 'id', not both.") if slug.present? && id.present?

      if id.present?
        parsed_id = Integer(id, exception: false)
        return error_response("Invalid 'id': must be a number.") if parsed_id.nil?

        id = parsed_id
      end

      post = Post.publicly_visible.includes(:tags).find_by(slug: slug.to_s) if slug.present?
      post ||= Post.publicly_visible.includes(:tags).find_by(id: id) if id.present?
      return error_response("Post not found.") unless post

      MCP::Tool::Response.new([ { type: "text", text: JSON.generate(
        id: post.id,
        slug: post.slug,
        title: post.title,
        body: post.body,
        excerpt: post.excerpt,
        tags: post.tags.map(&:name),
        published_at: post.published_at,
      ) } ])
    end

    private

    def error_response(text)
      MCP::Tool::Response.new([ { type: "text", text: text } ], error: true)
    end
  end
end
