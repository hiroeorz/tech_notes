xml.instruct! :xml, version: "1.0", encoding: "UTF-8"
xml.rss version: "2.0" do
  xml.channel do
    xml.title current_site_setting.blog_title
    xml.description current_site_setting.description
    xml.link root_url
    xml.language "ja"
    xml.lastBuildDate(@posts.first&.updated_at&.rfc2822 || Time.current.rfc2822)

    @posts.each do |post|
      xml.item do
        xml.title post.title
        xml.description post.excerpt
        xml.pubDate((post.published_at || post.created_at).rfc2822)
        xml.link post_url(post.slug)
        xml.guid post_url(post.slug)
        xml.category post.category.name
      end
    end
  end
end
