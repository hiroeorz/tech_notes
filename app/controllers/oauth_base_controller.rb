# typed: true

class OauthBaseController < ActionController::Base
  layout "application"

  helper_method :current_site_setting, :current_admin_user, :admin_signed_in?

  around_action :switch_locale

  private

  def switch_locale(&action)
    I18n.with_locale(determined_locale, &action)
  end

  def determined_locale
    locale = params[:locale] || cookies[:locale] || extract_locale_from_accept_language
    locale = locale.to_s.strip.to_sym
    locale = :en unless I18n.available_locales.include?(locale)

    locale
  end

  def extract_locale_from_accept_language
    request.env["HTTP_ACCEPT_LANGUAGE"].to_s.scan(/^[a-z]{2}(?=-|;|,|$)/).first
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
end
