class HomeController < ApplicationController
  def index
    @latest_posts = Post.publicly_visible.article.includes(:category, :tags).recent.limit(5)
    @experiments = Post.publicly_visible.experiment.includes(:tags).recent.limit(3)
    @daily_log = Post.publicly_visible.experiment.recent.first
    @top_filter_categories = Category.where(slug: %w[infrastructure aws automation programming security]).index_by(&:slug)
    load_sidebar
  end

  def profile
    return redirect_to root_path, alert: "プロフィールは現在公開されていません。" unless current_site_setting.profile_visible?

    load_sidebar
  end

  def about
    load_sidebar
  end
end
