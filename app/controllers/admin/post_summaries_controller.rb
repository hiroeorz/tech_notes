module Admin
  class PostSummariesController < BaseController
    def create
      summary = generator.generate(title: params[:title], body: params[:body])
      render json: { summary: summary }
    rescue PostSummaryGenerator::InvalidInput => error
      render json: { error: error.message }, status: :bad_request
    rescue PostSummaryGenerator::RateLimitError => error
      Rails.logger.warn("post_summary_generation_rate_limited: #{error.class}: #{error.message}")
      render json: { error: error.message }, status: :too_many_requests
    rescue PostSummaryGenerator::GenerationError => error
      Rails.logger.warn("post_summary_generation_failed: #{error.class}: #{error.message}")
      render json: { error: error.message }, status: :bad_gateway
    end

    private

    def generator
      PostSummaryGenerator.new
    end
  end
end
