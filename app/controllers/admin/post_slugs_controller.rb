module Admin
  class PostSlugsController < BaseController
    def create
      slug = generator.generate(title: params[:title], body: params[:body])
      render json: { slug: slug }
    rescue PostSlugGenerator::InvalidInput => error
      render json: { error: error.message }, status: :bad_request
    rescue PostSlugGenerator::RateLimitError => error
      Rails.logger.warn("post_slug_generation_rate_limited: #{error.class}: #{error.message}")
      render json: { error: error.message }, status: :too_many_requests
    rescue PostSlugGenerator::GenerationError => error
      Rails.logger.warn("post_slug_generation_failed: #{error.class}: #{error.message}")
      render json: { error: error.message }, status: :bad_gateway
    rescue StandardError => error
      Rails.logger.error("post_slug_generation_unexpected_error: #{error.class}: #{error.message}")
      render json: { error: t("flash.admin.post_slugs.generation_failed") }, status: :internal_server_error
    end

    private

    def generator
      PostSlugGenerator.new
    end
  end
end
