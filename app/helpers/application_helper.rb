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
end
