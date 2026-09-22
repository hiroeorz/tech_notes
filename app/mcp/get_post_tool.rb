# typed: true

class GetPostTool < MCP::Tool
  tool_name "get_post"
  description "Get the full content of a published post by slug or id. Body is returned as Markdown."
  input_schema(
    properties: {
      slug: { type: "string" },
      id: { type: "integer" }
    },
  )

  class << self
    def call(slug: nil, id: nil, server_context: nil)
      return error_response("Provide either 'slug' or 'id'.") if slug.blank? && id.blank?
      return error_response("Provide either 'slug' or 'id', not both.") if slug.present? && id.present?

      if id.present?
        parsed_id = parse_id(id)
        return error_response("Invalid 'id': must be an integer.") if parsed_id.nil?

        id = parsed_id
      end

      post = Post.publicly_visible.includes(:tags, :post_translations).find_by(slug: slug.to_s) if slug.present?
      post ||= Post.publicly_visible.includes(:tags, :post_translations).find_by(id: id) if id.present?
      return error_response("Post not found.") unless post

      content = post.localized_content(I18n.default_locale)
      MCP::Tool::Response.new([ { type: "text", text: JSON.generate(
        id: post.id,
        slug: post.slug,
        title: content[:title],
        body: content[:body],
        excerpt: content[:excerpt],
        tags: post.tags.map(&:name),
        published_at: post.published_at,
      ) } ])
    end

    private

    def parse_id(value)
      case value
      when Integer
        value
      when Float
        value.to_i if value.finite? && value.to_i.to_f == value
      when String
        stripped = value.strip
        return nil if stripped.empty?

        Integer(stripped, exception: false)
      else
        nil
      end
    end

    def error_response(text)
      MCP::Tool::Response.new([ { type: "text", text: text } ], error: true)
    end
  end
end
