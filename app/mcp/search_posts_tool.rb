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

      posts = Post.publicly_visible
        .where("LOWER(title) LIKE :pattern OR LOWER(excerpt) LIKE :pattern OR LOWER(body) LIKE :pattern", pattern: like_pattern(keyword))
      posts = filter_by_tags(posts, tags)
      posts = posts.includes(:tags).limit(limit_for(limit))

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
      {
        id: post.id,
        slug: post.slug,
        title: post.title,
        published_at: post.published_at,
        tags: post.tags.map(&:name),
        excerpt: post.excerpt
      }
    end

    def error_response(text)
      MCP::Tool::Response.new([ { type: "text", text: text } ], error: true)
    end
  end
end
