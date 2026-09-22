# typed: true

module Admin
  class ApiKeysController < BaseController
    def create
      unless %w[read write].include?(params[:scope].to_s)
        return create_failed
      end

      @api_key, @plain_token = ApiKey.issue(
        admin_user: current_admin_user,
        name: params[:name],
        scope: params[:scope].to_s
      )
      render :create
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique, ArgumentError
      create_failed
    end

    def revoke
      key = current_admin_user.api_keys.find(params[:id])
      key.revoke!
      redirect_to admin_settings_path, notice: t("flash.admin.api_keys.revoked")
    end

    private

    def create_failed
      redirect_to admin_settings_path, alert: t("flash.admin.api_keys.create_failed")
    end
  end
end
