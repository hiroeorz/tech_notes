module Admin
  class SessionsController < ApplicationController
    def new
    end

    def create
      if params[:email].blank? || params[:password].blank?
        @login_errors = []
        @login_errors << "メールアドレスを入力してください。" if params[:email].blank?
        @login_errors << "パスワードを入力してください。" if params[:password].blank?
        flash.now[:alert] = @login_errors.join(" ")
        render :new, status: :unprocessable_entity
        return
      end

      admin = AdminUser.find_by(email: params[:email].to_s.downcase)

      if admin&.authenticate(params[:password].to_s)
        session[:admin_user_id] = admin.id
        remember_admin(admin) if params[:remember_me] == "1"
        redirect_to admin_posts_path, notice: "ログインしました。"
      else
        flash.now[:alert] = "メールアドレスまたはパスワードが正しくありません。"
        render :new, status: :unprocessable_entity
      end
    end

    def destroy
      reset_session
      cookies.delete(:admin_user_id)
      redirect_to root_path, notice: "ログアウトしました。"
    end

    private

    def remember_admin(admin)
      cookies.permanent.signed[:admin_user_id] = {
        value: admin.id,
        httponly: true,
        same_site: :lax
      }
    end
  end
end
