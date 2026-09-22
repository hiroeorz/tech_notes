# typed: true

class UpdateDraftTool < MCP::Tool
  tool_name "update_draft"
  description "Update an existing draft post. Published posts cannot be updated with this tool."
  input_schema(
    properties: {
      id: { type: "integer" },
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
        parsed_id = parse_id(id)
        return error_response("Invalid 'id': must be an integer.") if parsed_id.nil?

        id = parsed_id
      end

      post = locate_post(api_key, id, slug)
      return error_response("Post not found.") unless post
      return error_response("Only draft posts can be updated.") unless post.draft?

      located_by_id = id.present?
      old_digest = PostTranslation.digest_for(title: post[:title], body: post[:body], excerpt: post[:excerpt])
      source_locale = post.post_translations.find { |translation| translation.content_digest == old_digest }&.locale
      has_update = !title.nil? || !body.nil? || (located_by_id && !slug.nil?) || !tags.nil?
      return error_response("Provide at least one field to update: title, body, slug, tags.") unless has_update

      begin
        Post.transaction do
          post.with_lock do
            return error_response("Only draft posts can be updated.") unless post.draft?

            post.title = title unless title.nil?
            post.body = body unless body.nil?
            post.slug = slug if located_by_id && !slug.nil?
            unless tags.nil?
              tag_list = Array(tags).flatten.map { |t| t.to_s.strip }.reject(&:blank?).uniq
              post.tag_names = tag_list.join(", ")
            end
            post.save!
            PostTranslationScheduler.call(post:, source_locale:) if source_locale
          end
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

    def locate_post(api_key, id, slug)
      owned_posts = Post.where(admin_user_id: api_key.admin_user_id).includes(:post_translations)
      if id.present?
        owned_posts.find_by(id: id)
      else
        owned_posts.find_by(slug: slug.to_s)
      end
    end

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

    def validation_summary(post)
      I18n.with_locale(:en) { post.errors.full_messages.join("; ") }
    end

    def error_response(text)
      MCP::Tool::Response.new([ { type: "text", text: text } ], error: true)
    end
  end
end
