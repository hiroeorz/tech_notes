# typed: true

class OauthBaseController < ActionController::Base
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
end
