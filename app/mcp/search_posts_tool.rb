# typed: true

class SearchPostsTool < MCP::Tool
  tool_name "search_posts"
  description "Search published blog posts by keyword. Returns post summaries (id, slug, title, published date, tags, excerpt)."
  input_schema(
    properties: {
      query: { type: "string" },
      tags: { type: "array", items: { type: "string" } },
      limit: { type: "number" }
    },
    required: [ "query" ],
  )

  DEFAULT_LIMIT = 10
  MAX_LIMIT = 50

  class << self
    def call(query: nil, tags: nil, limit: nil, server_context: nil)
      keyword = query.to_s.strip
      return error_response("Provide a non-empty 'query' to search.") if keyword.empty?

      default_locale = I18n.default_locale.to_s
      join = Post.sanitize_sql_array([
        <<~SQL.squish,
          LEFT OUTER JOIN post_translations localized_post_translations
            ON localized_post_translations.post_id = posts.id
            AND localized_post_translations.locale = ?
        SQL
        default_locale
      ])
      pattern = like_pattern(keyword)
      posts = Post.publicly_visible
        .joins(join)
        .where(
          "LOWER(COALESCE(localized_post_translations.title, posts.title)) LIKE :pattern " \
          "OR LOWER(COALESCE(localized_post_translations.excerpt, posts.excerpt)) LIKE :pattern " \
          "OR LOWER(COALESCE(localized_post_translations.body, posts.body)) LIKE :pattern",
          pattern: pattern
        )
      posts = filter_by_tags(posts, tags)
      posts = posts.includes(:tags, :post_translations).limit(limit_for(limit))

      MCP::Tool::Response.new([ { type: "text", text: JSON.generate(posts.map { |post| post_summary(post) }) } ])
    end

    private

    def like_pattern(keyword)
      "%#{Post.sanitize_sql_like(keyword.downcase)}%"
    end

    def filter_by_tags(posts, tags)
      tag_names = Array(tags).map { |tag| tag.to_s.strip }.reject(&:blank?).uniq
      return posts if tag_names.empty?

      matched_tags = Tag.where(name: tag_names)
      return posts.none if matched_tags.size < tag_names.size

      matched_tags.reduce(posts) { |scope, tag| scope.where(id: tag.posts.select(:id)) }
    end

    def limit_for(limit)
      return DEFAULT_LIMIT if limit.nil?

      limit.to_s.to_i.clamp(1, MAX_LIMIT)
    end

    def post_summary(post)
      content = post.localized_content(I18n.default_locale)
      {
        id: post.id,
        slug: post.slug,
        title: content[:title],
        published_at: post.published_at,
        tags: post.tags.map(&:name),
        excerpt: content[:excerpt]
      }
    end

    def error_response(text)
      MCP::Tool::Response.new([ { type: "text", text: text } ], error: true)
    end
  end
end
