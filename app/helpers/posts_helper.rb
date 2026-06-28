require "digest"

module PostsHelper
  def status_label(status)
    { "published" => "公開", "draft" => "下書き", "reviewing" => "レビュー中" }.fetch(status, status)
  end

  def kind_label(kind)
    { "article" => "記事", "experiment" => "実験ログ" }.fetch(kind, kind)
  end

  def extract_headings(markdown)
    markdown.to_s.lines.filter_map do |line|
      next unless line.start_with?("## ")

      title = line.delete_prefix("## ").strip
      [ heading_id(title), title ]
    end
  end

  def render_markdown(markdown)
    html = []
    in_code = false
    list_type = nil

    markdown.to_s.each_line do |raw_line|
      line = raw_line.chomp

      if line.start_with?("```")
        if in_code
          html << "</code></pre>"
          in_code = false
        else
          html << "<pre class=\"code-block\"><code>"
          in_code = true
        end
        next
      end

      if in_code
        html << ERB::Util.html_escape(line)
        next
      end

      if line.start_with?("- ")
        unless list_type == :ul
          html << "</#{list_type}>" if list_type
          html << "<ul>"
          list_type = :ul
        end
        html << "<li>#{inline_markdown(line.delete_prefix("- "))}</li>"
        next
      elsif line.match?(/^\d+\. /)
        unless list_type == :ol
          html << "</#{list_type}>" if list_type
          html << "<ol>"
          list_type = :ol
        end
        html << "<li>#{inline_markdown(line.sub(/^\d+\. /, ""))}</li>"
        next
      elsif list_type
        html << "</#{list_type}>"
        list_type = nil
      end

      html << case line
      when /^# (.+)$/
        "<h1>#{inline_markdown(Regexp.last_match(1))}</h1>"
      when /^## (.+)$/
        title = Regexp.last_match(1)
        "<h2 id=\"#{heading_id(title)}\">#{inline_markdown(title)}</h2>"
      when /^### (.+)$/
        "<h3>#{inline_markdown(Regexp.last_match(1))}</h3>"
      when /^!\[(.*?)\]\((.*?)\)$/
        image_markup(Regexp.last_match(1), Regexp.last_match(2))
      when /^> (.+)$/
        "<aside class=\"note-box\"><strong>ポイント:</strong> #{inline_markdown(Regexp.last_match(1))}</aside>"
      when ""
        ""
      else
        "<p>#{inline_markdown(line)}</p>"
      end
    end

    html << "</#{list_type}>" if list_type
    html.join("\n").html_safe
  end

  def inline_markdown(text)
    escaped = ERB::Util.html_escape(text)
    escaped.gsub(/`([^`]+)`/, '<code>\1</code>').gsub(/\*\*([^*]+)\*\*/, '<strong>\1</strong>').html_safe
  end

  def diagram_markup
    <<~HTML.html_safe
      <div class="diagram-node terraform">Terraform<br><small>実行環境</small></div>
      <div class="diagram-arrow">状態の読み書き</div>
      <div class="diagram-node s3">Amazon S3<br><small>State Backend</small></div>
      <div class="diagram-arrow">ロック制御</div>
      <div class="diagram-node dynamodb">Amazon DynamoDB<br><small>Lock Table</small></div>
    HTML
  end

  def image_markup(alt, source)
    return %(<figure class="article-diagram">#{diagram_markup}</figure>) if source.include?("remote-state-architecture")

    safe_alt = ERB::Util.html_escape(alt)
    safe_source = ERB::Util.html_escape(source)
    %(<figure class="article-image"><img src="#{safe_source}" alt="#{safe_alt}" loading="lazy"><figcaption>#{safe_alt}</figcaption></figure>)
  end

  def heading_id(title)
    title.parameterize.presence || "heading-#{Digest::SHA1.hexdigest(title)[0, 10]}"
  end
end
