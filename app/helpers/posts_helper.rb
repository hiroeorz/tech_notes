module PostsHelper
  def status_label(status)
    { "published" => "公開", "draft" => "下書き", "reviewing" => "レビュー中" }.fetch(status, status)
  end

  def kind_label(kind)
    { "article" => "記事", "experiment" => "実験ログ" }.fetch(kind, kind)
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
