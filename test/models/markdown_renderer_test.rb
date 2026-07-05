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

  test "highlights fenced code blocks by language" do
    markdown = <<~MARKDOWN
      ```ruby
      puts "hello"
      ```

      ```bash
      echo "hello"
      ```

      ```elixir
      IO.puts("hello")
      ```

      ```javascript
      console.log("hello")
      ```
    MARKDOWN

    html = MarkdownRenderer.new(markdown).render

    assert_includes html, "code-block"
    assert_includes html, "highlight"
    assert_includes html, "language-ruby"
    assert_includes html, "language-shell"
    assert_includes html, "language-elixir"
    assert_includes html, "language-javascript"
    assert_includes html, "<span"
    assert_not_includes html, "style="
  end

  test "keeps code blocks without a language unhighlighted" do
    markdown = <<~MARKDOWN
      ```
      puts "hello"
      ```
    MARKDOWN

    html = MarkdownRenderer.new(markdown).render

    assert_includes html, "code-block"
    assert_not_includes html, "language-ruby"
    assert_not_includes html, "highlight"
    assert_includes html, "puts"
  end

  test "decorates code blocks with filename from lang attribute" do
    html = MarkdownRenderer.new(<<~MARKDOWN).render
      ```ruby:test.rb
      puts "hello"
      ```

      ```elixir:app.ex
      IO.puts("hi")
      ```

      ```:notes.txt
      plain text
      ```

      ```javascript
      console.log("no filename")
      ```
    MARKDOWN

    doc = Nokogiri::HTML5.fragment(html)

    blocks = doc.css("pre.code-block")
    assert_equal 4, blocks.size

    ruby_block = blocks[0]
    assert_equal "test.rb", ruby_block["data-filename"]
    assert_includes ruby_block.classes, "highlight"
    assert_includes ruby_block.classes, "language-ruby"

    elixir_block = blocks[1]
    assert_equal "app.ex", elixir_block["data-filename"]
    assert_includes elixir_block.classes, "highlight"
    assert_includes elixir_block.classes, "language-elixir"

    text_block = blocks[2]
    assert_equal "notes.txt", text_block["data-filename"]
    assert_not_includes text_block.classes, "highlight"

    js_block = blocks[3]
    assert_nil js_block["data-filename"]
    assert_includes js_block.classes, "highlight"
  end

  test "decorates markdown images for article lightbox" do
    html = MarkdownRenderer.new("![構成図](/images/architecture.png)").render

    assert_includes html, %(<figure class="article-image">)
    assert_includes html, %(class="article-image-viewer-trigger")
    assert_includes html, %(src="/images/architecture.png")
    assert_includes html, %(alt="構成図")
    assert_includes html, %(loading="lazy")
    assert_includes html, %(role="button")
    assert_includes html, %(tabindex="0")
    assert_includes html, "<figcaption>構成図</figcaption>"
  end
end
