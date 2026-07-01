require "digest"
require "nokogiri"
require "rouge"

class MarkdownRenderer
  COMMONMARK_OPTIONS = {
    extension: {
      autolink: true,
      strikethrough: true,
      table: true,
      tagfilter: true,
      tasklist: true
    },
    parse: {
      smart: true
    }
  }.freeze

  ALLOWED_TAGS = %w[
    a aside blockquote br code del div em figcaption figure h1 h2 h3 h4 h5 h6
    hr img input li ol p pre small span strong table tbody td th thead tr ul
  ].freeze

  ALLOWED_ATTRIBUTES = %w[
    alt checked class disabled href id loading rel src type
  ].freeze

  def initialize(markdown)
    @markdown = markdown.to_s
  end

  def render
    sanitize(decorated_fragment.to_html)
  end

  def headings
    decorated_fragment.css("h2").map do |heading|
      [ heading["id"], heading.text.strip ]
    end
  end

  def self.heading_id(title)
    title.parameterize.presence || "heading-#{Digest::SHA1.hexdigest(title)[0, 10]}"
  end

  private

  def decorated_fragment
    fragment = Nokogiri::HTML5.fragment(render_commonmark)
    decorate_headings(fragment)
    decorate_code_blocks(fragment)
    decorate_tables(fragment)
    decorate_links(fragment)
    decorate_tasks(fragment)
    decorate_images(fragment)
    fragment
  end

  def render_commonmark
    Commonmarker.to_html(normalized_markdown, options: COMMONMARK_OPTIONS)
  end

  def normalized_markdown
    normalized = []
    previous_list_item = false

    @markdown.each_line do |line|
      current_list_item = line.match?(/\A\s*(?:[-*+]|\d+\.)\s+/)
      current_continuation = line.blank? || current_list_item || line.match?(/\A\s{2,}/)

      normalized << "\n" if previous_list_item && !current_continuation
      normalized << line
      previous_list_item = current_list_item
    end

    normalized.join
  end

  def decorate_headings(fragment)
    fragment.css("h2").each do |heading|
      heading.css("a.anchor").remove
      heading["id"] ||= self.class.heading_id(heading.text.strip)
    end
  end

  def decorate_code_blocks(fragment)
    fragment.css("pre").each do |pre|
      pre["class"] = append_class(pre["class"], "code-block")
      highlight_code_block(pre)
    end
  end

  def decorate_tables(fragment)
    fragment.css("table").each do |table|
      table["class"] = append_class(table["class"], "markdown-table")
    end
  end

  def decorate_links(fragment)
    fragment.css("a[href]").each do |link|
      link["rel"] = "noreferrer"
    end
  end

  def decorate_tasks(fragment)
    fragment.css("li").each do |list_item|
      next unless list_item.at_css("input[type='checkbox']")

      list_item["class"] = append_class(list_item["class"], "task-list-item")
    end
  end

  def decorate_images(fragment)
    fragment.css("img").each do |image|
      if image["src"].to_s.include?("remote-state-architecture")
        image.replace(Nokogiri::HTML5.fragment(%(<figure class="article-diagram">#{diagram_markup}</figure>)))
        next
      end

      image["loading"] = "lazy"
      figure = Nokogiri::XML::Node.new("figure", fragment)
      figure["class"] = "article-image"
      caption = Nokogiri::XML::Node.new("figcaption", fragment)
      caption.content = image["alt"].to_s
      image.replace(figure)
      figure.add_child(image)
      figure.add_child(caption)
    end
  end

  def append_class(current, class_name)
    classes = current.to_s.split
    classes << class_name
    classes.uniq.join(" ")
  end

  def highlight_code_block(pre)
    language = pre["lang"].to_s.strip.presence
    code = pre.at_css("code")
    return if language.blank? || code.blank?
    return if language.in?(%w[text plaintext])

    lexer = Rouge::Lexer.find_fancy(language, code.text)
    return unless lexer

    formatter = Rouge::Formatters::HTML.new
    highlighted = formatter.format(lexer.lex(code.text))
    code.children.remove
    code.add_child(Nokogiri::HTML5.fragment(highlighted))
    pre["class"] = append_class(pre["class"], "highlight")
    pre["class"] = append_class(pre["class"], "language-#{lexer.tag}")
    code["class"] = append_class(code["class"], "highlight")
  rescue Rouge::Guesser::Ambiguous
    nil
  end

  def diagram_markup
    <<~HTML
      <div class="diagram-node terraform">Terraform<br><small>実行環境</small></div>
      <div class="diagram-arrow">状態の読み書き</div>
      <div class="diagram-node s3">Amazon S3<br><small>State Backend</small></div>
      <div class="diagram-arrow">ロック制御</div>
      <div class="diagram-node dynamodb">Amazon DynamoDB<br><small>Lock Table</small></div>
    HTML
  end

  def sanitize(html)
    Rails::HTML5::SafeListSanitizer.new.sanitize(
      html,
      tags: ALLOWED_TAGS,
      attributes: ALLOWED_ATTRIBUTES
    )
  end
end
