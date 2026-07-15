class CommentsController < ApplicationController
  before_action :set_post
  rate_limit to: 5, within: 1.minute, only: :create, by: -> { request.remote_ip }, with: -> { render_too_many_requests }

  def create
    @comment = @post.comments.new(comment_params)
    @comment.ip_address = request.remote_ip

    if turnstile_valid? && @comment.save
      CommentNotificationJob.perform_later(@comment)
      redirect_to post_path(@post.slug, anchor: "comments"), notice: t("flash.comments.created")
    else
      @comments = @post.comments.oldest
      flash.now[:alert] = @comment.errors.full_messages.first if @comment.errors.any?
      flash.now[:alert] = t("flash.comments.spam") unless turnstile_valid?
      set_post_meta(@post)
      @related_posts = Post.publicly_visible.includes(:post_translations).where(category: @post.category).where.not(id: @post.id).recent.limit(3)
      @toc = helpers.extract_headings(@post.localized_body)
      load_sidebar
      render "posts/show", status: :unprocessable_entity
    end
  end

  private

  def set_post
    @post = Post.publicly_visible.includes(:post_translations).find_by!(slug: params[:post_slug])
  end

  def comment_params
    params.require(:comment).permit(:author_name, :body)
  end

  def turnstile_valid?
    token = params["cf-turnstile-response"]
    TurnstileVerifier.verify(token, remote_ip: request.remote_ip)
  end

  def set_post_meta(post)
    @page_title = "#{post.localized_title} | #{current_site_setting.blog_title}"
    @page_description = post.localized_excerpt
    @page_type = "article"
    @page_url = post_url(post.slug)
  end

  def render_too_many_requests
    slug = @post&.slug || params[:post_slug]
    redirect_to post_path(slug, anchor: "comments"), alert: t("flash.comments.rate_limit")
  end
end
