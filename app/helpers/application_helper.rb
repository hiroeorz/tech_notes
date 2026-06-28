module ApplicationHelper
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
