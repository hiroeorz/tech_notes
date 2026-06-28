module Admin
  class BaseController < ApplicationController
    before_action :require_admin

    private

    def require_admin
      redirect_to admin_login_path, alert: "ログインしてください。" unless admin_signed_in?
    end
  end
end
