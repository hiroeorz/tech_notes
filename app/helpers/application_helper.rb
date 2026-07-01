module ApplicationHelper
  def highlight_code(code, language:)
    lexer = Rouge::Lexer.find_fancy(language, code)
    return ERB::Util.html_escape(code) unless lexer

    Rouge::Formatters::HTML.new.format(lexer.lex(code)).html_safe
  rescue Rouge::Guesser::Ambiguous
    ERB::Util.html_escape(code)
  end

  def category_icon(icon_key)
    {
      "cloud" => "☁",
      "aws" => "▱",
      "azure" => "◇",
      "automation" => "⚙",
      "code" => "</>",
      "security" => "▣",
      "ops" => "▤",
      "poem" => "✎"
    }.fetch(icon_key, "▢")
  end

  def social_link(label, url, **options)
    return unless url.present?

    link_to label, url, **options
  end
end
