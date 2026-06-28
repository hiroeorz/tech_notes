module Admin
  class SettingsController < BaseController
    def show
      @setting = current_site_setting
    end

    def update
      @setting = current_site_setting

      if @setting.update(setting_params)
        if password_params_present? && !update_password
          flash.now[:alert] = "パスワードを更新できませんでした。入力内容を確認してください。"
          render :show, status: :unprocessable_entity
        else
          redirect_to admin_settings_path, notice: "設定を保存しました。"
        end
      else
        render :show, status: :unprocessable_entity
      end
    end

    private

    def setting_params
      params.require(:site_setting).permit(
        :blog_title, :tagline, :site_url, :description, :ogp_image_path,
        :profile_name, :profile_title, :profile_email, :profile_bio, :profile_image_path,
        :github_url, :x_url, :rss_url, :zenn_url, :note_url,
        :profile_visible, :sns_visible, :default_theme, :posts_per_page,
        :ogp_image, :profile_image
      )
    end

    def password_params_present?
      params[:current_password].present? || params[:new_password].present? || params[:new_password_confirmation].present?
    end

    def update_password
      return false unless current_admin_user.authenticate(params[:current_password].to_s)
      return false unless params[:new_password].present? && params[:new_password] == params[:new_password_confirmation]
      return false unless params[:new_password].length >= 8 && params[:new_password].match?(/[a-zA-Z]/) && params[:new_password].match?(/\d/)

      current_admin_user.password = params[:new_password]
      current_admin_user.save!
      true
    end
  end
end
