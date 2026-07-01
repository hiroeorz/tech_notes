module Admin
  class BaseController < ApplicationController
    before_action :require_admin

    private

    def require_admin
      return if admin_signed_in?

      respond_to do |format|
        format.json { render json: { error: "ログインし直してから実行してください。" }, status: :unauthorized }
        format.any { redirect_to admin_login_path, alert: "ログインしてください。" }
      end
    end
  end
end
