class LocaleController < ApplicationController
  skip_before_action :redirect_to_localized_url

  def update
    locale = params[:locale].to_s.strip.to_sym
    return redirect_back(fallback_location: root_path) unless I18n.available_locales.include?(locale)

    cookies.permanent[:locale] = locale.to_s

    referrer = request.referer.to_s
    if referrer.present?
      begin
        uri = URI.parse(referrer)
        new_path = uri.path.sub(%r{^/(en|ja)?(/?)}, "/#{locale}\\2")
        new_path = "/#{locale}" if new_path.empty? || new_path == "/"
        uri.path = new_path
        redirect_to uri.to_s, status: 303
      rescue URI::InvalidURIError
        redirect_to root_path(locale: locale)
      end
    else
      redirect_to root_path(locale: locale)
    end
  end
end
