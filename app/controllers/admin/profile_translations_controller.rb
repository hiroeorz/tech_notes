module Admin
  class ProfileTranslationsController < BaseController
    def create
      translation = translator.translate(
        profile_title: params[:profile_title].to_s,
        profile_bio: params[:profile_bio].to_s
      )
      render json: translation
    rescue ProfileTranslator::InvalidInput => error
      render json: { error: error.message }, status: :bad_request
    rescue ProfileTranslator::RateLimitError => error
      Rails.logger.warn("profile_translation_rate_limited: #{error.class}: #{error.message}")
      render json: { error: error.message }, status: :too_many_requests
    rescue ProfileTranslator::GenerationError => error
      Rails.logger.warn("profile_translation_failed: #{error.class}: #{error.message}")
      render json: { error: error.message }, status: :bad_gateway
    rescue StandardError => error
      Rails.logger.error("profile_translation_unexpected_error: #{error.class}: #{error.message}")
      render json: { error: t("flash.admin.profile_translations.generation_failed") }, status: :internal_server_error
    end

    private

    def translator
      ProfileTranslator.new
    end
  end
end
