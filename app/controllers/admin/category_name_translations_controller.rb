module Admin
  class CategoryNameTranslationsController < BaseController
    def create
      translation = generator.generate(name: params[:name])
      render json: { name_en: translation }
    rescue CategoryNameTranslator::InvalidInput => error
      render json: { error: error.message }, status: :bad_request
    rescue CategoryNameTranslator::RateLimitError => error
      Rails.logger.warn("category_name_translation_rate_limited: #{error.class}: #{error.message}")
      render json: { error: error.message }, status: :too_many_requests
    rescue CategoryNameTranslator::GenerationError => error
      Rails.logger.warn("category_name_translation_failed: #{error.class}: #{error.message}")
      render json: { error: error.message }, status: :bad_gateway
    rescue StandardError => error
      Rails.logger.error("category_name_translation_unexpected_error: #{error.class}: #{error.message}")
      render json: { error: t("flash.admin.category_name_translations.generation_failed") }, status: :internal_server_error
    end

    private

    def generator
      CategoryNameTranslator.new
    end
  end
end
