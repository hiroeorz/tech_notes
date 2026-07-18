# typed: true

module Admin
  class ProfileTranslationsController < BaseController
    SUPPORTED_FIELDS = %w[title bio].freeze

    def create
      field = params[:field].to_s
      return render json: { error: "Invalid field" }, status: :bad_request unless field.in?(SUPPORTED_FIELDS)

      translation = translator.translate_field(field: field, value: params[:value].to_s)
      render json: { "profile_#{field}_en" => translation }
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
