module ApplicationHelper
  def highlight_code(code, language:)
    lexer = Rouge::Lexer.find_fancy(language, code)
    return ERB::Util.html_escape(code) unless lexer

    Rouge::Formatters::HTML.new.format(lexer.lex(code)).html_safe
  rescue Rouge::Guesser::Ambiguous
    ERB::Util.html_escape(code)
  end

  def icon_key_options
    [
      [ "☁ #{t('helpers.category.icon_cloud')}", "cloud" ],
      [ "▱ #{t('helpers.category.icon_aws')}", "aws" ],
      [ "◇ #{t('helpers.category.icon_azure')}", "azure" ],
      [ "⚙ #{t('helpers.category.icon_automation')}", "automation" ],
      [ "</> #{t('helpers.category.icon_code')}", "code" ],
      [ "▣ #{t('helpers.category.icon_security')}", "security" ],
      [ "▤ #{t('helpers.category.icon_ops')}", "ops" ],
      [ "✎ #{t('helpers.category.icon_poem')}", "poem" ]
    ]
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

  def turnstile_site_key
    if Rails.env.test? || Rails.env.development?
      "1x00000000000000000000AA"
    else
      ENV["TURNSTILE_SITE_KEY"].to_s
    end
  end

  def turnstile_enabled?
    turnstile_site_key.present?
  end
end
