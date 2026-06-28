class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  helper_method :current_site_setting, :current_admin_user, :admin_signed_in?

  private

  def current_site_setting
    @current_site_setting ||= SiteSetting.current
  end

  def current_admin_user
    @current_admin_user ||= AdminUser.find_by(id: session[:admin_user_id] || cookies.signed[:admin_user_id])
  end

  def admin_signed_in?
    current_admin_user.present?
  end

  def load_sidebar
    @categories = sidebar_categories
    @archives = Post.publicly_visible.group_by { |post| post.display_date.beginning_of_month }
  end

  def sidebar_categories
    counts = Post.publicly_visible.group(:category_id).count

    Category.ordered.to_a.each do |category|
      category.define_singleton_method(:posts_count) { counts.fetch(category.id, 0) }
    end
  end
end
