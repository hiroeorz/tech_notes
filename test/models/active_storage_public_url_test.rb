require "test_helper"

class ActiveStoragePublicUrlTest < ActiveSupport::TestCase
  test "builds a public URL from a key" do
    with_configured_base_url("https://cdn.example.com") do
      assert_equal "https://cdn.example.com/variants/abc", ActiveStoragePublicUrl.for_key("variants/abc")
      assert_equal "https://cdn.example.com/variants/abc", ActiveStoragePublicUrl.for_key("/variants/abc")
    end
  end

  test "builds a public URL from a blob" do
    blob = ActiveStorage::Blob.new(key: "images/hero.png")

    with_configured_base_url("https://cdn.example.com") do
      assert_equal "https://cdn.example.com/images/hero.png", ActiveStoragePublicUrl.for(blob)
    end
  end

  test "raises when the public base URL is not configured" do
    with_configured_base_url(nil) do
      assert_raises(ArgumentError) { ActiveStoragePublicUrl.for_key("images/hero.png") }
    end
  end

  test "rejects blank keys" do
    with_configured_base_url("https://cdn.example.com") do
      assert_raises(ArgumentError) { ActiveStoragePublicUrl.for_key("") }
      assert_raises(ArgumentError) { ActiveStoragePublicUrl.for_key(nil) }
    end
  end

  test "detects blobs stored in the current service" do
    blob = ActiveStorage::Blob.new(key: "images/hero.png", service_name: "test")
    assert ActiveStoragePublicUrl.current_service?(blob)

    blob.service_name = "local"
    assert_not ActiveStoragePublicUrl.current_service?(blob)
  end

  private

  def with_configured_base_url(url)
    original = ActiveStoragePublicUrl.method(:configured_base_url)
    ActiveStoragePublicUrl.define_singleton_method(:configured_base_url) { url }
    yield
  ensure
    ActiveStoragePublicUrl.define_singleton_method(:configured_base_url, original)
  end
end
