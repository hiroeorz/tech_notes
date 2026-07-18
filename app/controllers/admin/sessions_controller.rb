# typed: true

module Admin
  class SessionsController < ApplicationController
    def new
    end

    def create
      if params[:email].blank? || params[:password].blank?
        @login_errors = []
        @login_errors << t("flash.admin.sessions.email_blank") if params[:email].blank?
        @login_errors << t("flash.admin.sessions.password_blank") if params[:password].blank?
        flash.now[:alert] = @login_errors.join(" ")
        render :new, status: :unprocessable_entity
        return
      end

      unless turnstile_valid?
        flash.now[:alert] = t("flash.admin.sessions.spam")
        render :new, status: :unprocessable_entity
        return
      end

      admin = AdminUser.find_by(email: params[:email].to_s.downcase)

      if admin&.authenticate(params[:password].to_s)
        session[:admin_user_id] = admin.id
        remember_admin(admin) if params[:remember_me] == "1"
        redirect_to admin_posts_path, notice: t("flash.admin.sessions.login_success")
      else
        flash.now[:alert] = t("flash.admin.sessions.login_failure")
        render :new, status: :unprocessable_entity
      end
    end

    def destroy
      reset_session
      cookies.delete(:admin_user_id)
      redirect_to root_path, notice: t("flash.admin.sessions.logout_success")
    end

    private

    def remember_admin(admin)
      cookies.permanent.signed[:admin_user_id] = {
        value: admin.id,
        httponly: true,
        same_site: :lax
      }
    end

    def turnstile_valid?
      return true if Rails.env.test?
      return true unless helpers.turnstile_enabled?

      token = params["cf-turnstile-response"]
      TurnstileVerifier.verify(token, remote_ip: request.remote_ip)
    end
  end
end
