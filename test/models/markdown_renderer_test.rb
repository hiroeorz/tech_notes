require "test_helper"

class MarkdownRendererTest < ActiveSupport::TestCase
  test "renders markdown to sanitized html" do
    markdown = "## 見出し\n\n- リスト1\n- リスト2\n\n<script>alert('xss')</script>"
    renderer = MarkdownRenderer.new(markdown)
    html = renderer.render

    assert_includes html, "h2"
    assert_includes html, "見出し"
    assert_includes html, "ul"
    assert_not_includes html, "<script>"
  end

  test "extracts headings" do
    markdown = "## セクション1\n\n本文\n\n## セクション2"
    renderer = MarkdownRenderer.new(markdown)
    headings = renderer.headings

    assert_equal 2, headings.size
    assert_equal "セクション1", headings[0][1]
    assert_equal "セクション2", headings[1][1]
  end
end
