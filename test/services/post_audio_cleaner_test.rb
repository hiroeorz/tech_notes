require "test_helper"

class PostAudioCleanerTest < ActiveSupport::TestCase
  test "strips code blocks" do
    input = "Text\n```ruby\nputs 'hello'\n```\nEnd"
    assert_equal "Text End", PostAudioCleaner.clean(input)
  end

  test "strips inline code" do
    input = "Use the `bin/rails` command."
    assert_equal "Use the command.", PostAudioCleaner.clean(input)
  end

  test "strips images" do
    input = "Text ![alt](image.png) end"
    assert_equal "Text end", PostAudioCleaner.clean(input)
  end

  test "preserves link text but strips URL" do
    input = "Visit [GitHub](https://github.com)"
    assert_equal "Visit GitHub", PostAudioCleaner.clean(input)
  end

  test "strips HTML tags" do
    input = "Hello <strong>world</strong>"
    assert_equal "Hello world", PostAudioCleaner.clean(input)
  end

  test "strips heading markers but keeps text" do
    input = "## Hello World\n### Subtitle"
    assert_equal "Hello World Subtitle", PostAudioCleaner.clean(input)
  end

  test "removes horizontal rules" do
    input = "Text\n---\nMore"
    assert_equal "Text More", PostAudioCleaner.clean(input)
  end

  test "collapses excessive whitespace" do
    input = "Hello   world\n\n\nMore"
    assert_equal "Hello world More", PostAudioCleaner.clean(input)
  end

  test "returns empty string for blank input" do
    assert_equal "", PostAudioCleaner.clean("")
    assert_equal "", PostAudioCleaner.clean("   ")
    assert_equal "", PostAudioCleaner.clean("```code```")
  end

  test "preserves regular paragraph text" do
    input = "This is a normal paragraph with some text."
    assert_equal "This is a normal paragraph with some text.", PostAudioCleaner.clean(input)
  end

  test "handles nil input" do
    assert_equal "", PostAudioCleaner.clean(nil)
  end
end
