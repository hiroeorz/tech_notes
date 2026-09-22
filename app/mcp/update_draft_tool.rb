# typed: true

class UpdateDraftTool < MCP::Tool
  tool_name "update_draft"
  description "Update an existing draft post. Published posts cannot be updated with this tool."
  input_schema(
    properties: {
      id: { type: "number" },
      slug: { type: "string" },
      title: { type: "string" },
      body: { type: "string" },
      tags: { type: "array", items: { type: "string" } }
    },
  )

  class << self
    def call(id: nil, slug: nil, title: nil, body: nil, tags: nil, server_context: nil)
      api_key = server_context && server_context[:api_key]
      return error_response("Missing API key context.") unless api_key
      return error_response("Forbidden: this tool requires write scope.") unless api_key.write?
      return error_response("Provide either 'id' or 'slug'.") if id.blank? && slug.blank?

      if id.present?
        parsed_id = Integer(id, exception: false)
        return error_response("Invalid 'id': must be a number.") if parsed_id.nil?

        id = parsed_id
      end

      post = locate_post(api_key, id, slug)
      return error_response("Post not found.") unless post
      return error_response("Only draft posts can be updated.") unless post.draft?

      located_by_id = id.present?
      fields_assigned = false
      unless title.nil?
        post.title = title
        fields_assigned = true
      end
      unless body.nil?
        post.body = body
        fields_assigned = true
      end
      if located_by_id && !slug.nil?
        post.slug = slug
        fields_assigned = true
      end
      unless tags.nil?
        tag_list = Array(tags).flatten.map { |t| t.to_s.strip }.reject(&:blank?).uniq
        post.tag_names = tag_list.join(", ")
        fields_assigned = true
      end
      return error_response("Provide at least one field to update: title, body, slug, tags.") unless fields_assigned

      begin
        post.save!
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

    def locate_post(api_key, id, slug)
      owned_posts = Post.where(admin_user_id: api_key.admin_user_id)
      if id.present?
        owned_posts.find_by(id: id)
      else
        owned_posts.find_by(slug: slug.to_s)
      end
    end

    def validation_summary(post)
      I18n.with_locale(:en) { post.errors.full_messages.join("; ") }
    end

    def error_response(text)
      MCP::Tool::Response.new([ { type: "text", text: text } ], error: true)
    end
  end
end
