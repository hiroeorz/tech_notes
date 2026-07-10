class HomeController < ApplicationController
  def index
    @latest_posts = Post.publicly_visible.article.includes(:category, :tags, :post_translations).recent.limit(5)
    @experiments = Post.publicly_visible.experiment.includes(:tags, :post_translations).recent.limit(21)
    @daily_log = Post.publicly_visible.experiment.includes(:post_translations).recent.first
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
