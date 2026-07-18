module PostsHelper
  def status_label(status)
    t("helpers.post.status_#{status}", default: status)
  end

  def extract_headings(markdown)
    MarkdownRenderer.new(markdown).headings
  end

  def render_markdown(markdown)
    MarkdownRenderer.new(markdown).render.html_safe
  end

  def heading_id(title)
    MarkdownRenderer.heading_id(title)
  end

  def share_text_for_x(post)
    if I18n.locale == :en
      "#{post.localized_title}\n\n#{post.localized_excerpt}"
    else
      post.localized_title
    end
  end
end
