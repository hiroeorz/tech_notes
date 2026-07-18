# typed: true

class HomeController < ApplicationController
  def index
    @popular_posts = T.unsafe(Post.publicly_visible.includes(:category, :tags, :post_translations)).most_viewed.limit(3)
    @latest_posts = Post.publicly_visible.includes(:category, :tags, :post_translations).recent.limit(21)
    @daily_log = Post.publicly_visible.includes(:post_translations).recent.first
    @top_filter_categories = Category.where(slug: %w[infrastructure aws automation programming security ai-development]).index_by(&:slug)
    load_sidebar
  end

  def profile
    return redirect_to root_path, alert: t("flash.profile.not_visible") unless current_site_setting.profile_visible?

    load_sidebar
  end

  def about
    load_sidebar
  end
end
