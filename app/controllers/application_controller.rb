class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  around_action :switch_locale
  helper_method :current_site_setting, :current_admin_user, :admin_signed_in?

  private

  def switch_locale(&action)
    locale = cookies[:locale].presence || extract_locale_from_accept_language
    locale = locale.to_s.strip.to_sym
    locale = :en unless I18n.available_locales.include?(locale)
    I18n.with_locale(locale, &action)
  end

  def extract_locale_from_accept_language
    accepted = request.env["HTTP_ACCEPT_LANGUAGE"].to_s
    accepted.scan(/^[a-z]{2}(?=-|;|,|$)/).first
  end

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
