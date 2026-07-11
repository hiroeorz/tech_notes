class LlmsTxtController < ApplicationController
  skip_before_action :redirect_to_localized_url
  skip_after_action :set_content_language

  def show
    expires_in 1.hour, public: true
    render plain: llms_txt_content, content_type: "text/plain"
  end

  private

  def llms_txt_content
    Rails.cache.fetch(cache_key, expires_in: 1.hour) do
      render_to_string("llms_txt/show", layout: false)
    end
  end

  def cache_key
    setting_ts = SiteSetting.maximum(:updated_at)&.to_fs(:usec) || "0"
    post_ts = Post.publicly_visible.maximum(:updated_at)&.to_fs(:usec) || "0"
    "llms_txt/v1/#{setting_ts}/#{post_ts}"
  end
end
