module PostsHelper
  def status_label(status)
    t("helpers.post.status_#{status}", default: status)
  end

  def kind_label(kind)
    t("helpers.post.kind_#{kind}", default: kind)
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
end
