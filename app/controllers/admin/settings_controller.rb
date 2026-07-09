module Admin
  class SettingsController < BaseController
    def show
      @setting = current_site_setting
    end

    def update
      @setting = current_site_setting

      unless password_change_valid?
        flash.now[:alert] = t("flash.admin.settings.password_failed")
        render :show, status: :unprocessable_entity
        return
      end

      ActiveRecord::Base.transaction do
        @setting.update!(setting_params)
        apply_password_change! if password_params_present?
      end

      redirect_to admin_settings_path, notice: t("flash.admin.settings.saved")
    rescue ActiveRecord::RecordInvalid
      render :show, status: :unprocessable_entity
    end

    private

    def password_change_valid?
      return true unless password_params_present?

      current_admin_user.authenticate(params[:current_password].to_s) &&
        params[:new_password].present? &&
        params[:new_password] == params[:new_password_confirmation] &&
        params[:new_password].length >= 8 &&
        params[:new_password].match?(/[a-zA-Z]/) &&
        params[:new_password].match?(/\d/)
    end

    def apply_password_change!
      current_admin_user.password = params[:new_password]
      current_admin_user.save!
    end

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
  end
end
