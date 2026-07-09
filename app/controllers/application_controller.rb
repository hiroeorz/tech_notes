class ApplicationController < ActionController::Base
  allow_browser versions: :modern
  stale_when_importmap_changes

  around_action :switch_locale
  before_action :redirect_to_localized_url
  after_action :set_content_language

  helper_method :current_site_setting, :current_admin_user, :admin_signed_in?

  private

  def switch_locale(&action)
    I18n.with_locale(determined_locale, &action)
  end

  def determined_locale
    locale = params[:locale] || cookies[:locale] || extract_locale_from_accept_language
    locale = locale.to_s.strip.to_sym
    locale = :en unless I18n.available_locales.include?(locale)

    if params[:locale].present? && cookies[:locale] != locale.to_s
      cookies.permanent[:locale] = locale.to_s
    end

    locale
  end

  def extract_locale_from_accept_language
    accepted = request.env["HTTP_ACCEPT_LANGUAGE"].to_s
    accepted.scan(/^[a-z]{2}(?=-|;|,|$)/).first
  end

  def redirect_to_localized_url
    return if params[:locale].present?
    return unless request.get? || request.head?
    return if request.path.start_with?("/up")
    return if admin_controller?

    locale = determined_locale
    redirect_to url_for(locale: locale), status: 302
  end

  def set_content_language
    response.headers["Content-Language"] = I18n.locale.to_s
  end

  def default_url_options
    if params[:locale].present? && !admin_namespace?
      { locale: I18n.locale }
    else
      {}
    end
  end

  def admin_namespace?
    controller_path.start_with?("admin/")
  end
  alias admin_controller? admin_namespace?

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
