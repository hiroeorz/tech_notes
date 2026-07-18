# typed: true

module Admin
  class PostsController < BaseController
    before_action :set_post, only: [ :show, :preview, :edit, :update, :destroy ]

    def index
      @posts = Post.includes(:category, :tags, :post_translations).recent
      @posts = T.unsafe(@posts).search_by_title(params[:q], locale: I18n.locale) if params[:q].present?
      @posts = @posts.where(category_id: params[:category_id]) if params[:category_id].present?
      @posts = @posts.where(status: params[:status]) if params[:status].present? && Post.statuses.key?(params[:status])
      @posts = @posts.reorder(updated_at: :asc) if params[:sort] == "oldest"
      @page = [ params[:page].to_i, 1 ].max
      @per_page = current_site_setting.posts_per_page
      @filtered_count = @posts.count
      @total_pages = [ (@filtered_count / @per_page.to_f).ceil, 1 ].max
      @page = [ @page, @total_pages ].min
      @posts = @posts.limit(@per_page).offset((@page - 1) * @per_page)
      @categories = Category.ordered
      @has_unread_comments = Comment.where("created_at > ?", current_admin_user.last_comments_read_at || Time.at(0)).exists?
      @total_count = Post.count
      @published_count = Post.published.count
      @draft_count = Post.draft.count
      @reviewing_count = Post.reviewing.count
    end

    def show
      redirect_to post_path(@post.slug)
    end

    def preview
      @post = Post.includes(:category, :tags, :post_translations, :post_audios).find_by!(slug: params[:slug])
      @page_title = "#{t('admin.posts.form.preview')}: #{@post.localized_title} | #{current_site_setting.blog_title}"
      @page_description = @post.localized_excerpt
      @page_type = "article"
      @page_url = preview_admin_post_url(@post.slug)
      @toc = helpers.extract_headings(@post.localized_body)
      @related_posts = Post.includes(:post_translations).where(category: @post.category).where.not(id: @post.id).recent.limit(3)
      render "posts/show"
    end

    def markdown_preview
      render html: MarkdownRenderer.new(params[:body].to_s).render.html_safe, layout: false
    end

    def new
      @post = Post.new(status: :draft, published_at: Time.current)
      prepare_form(use_localized_content: false)
    end

    def edit
      prepare_form(use_localized_content: true)
    end

    def create
      @post = current_admin_user.posts.new(post_params)
      assign_tag_names

      if save_post
        redirect_to edit_admin_post_path(@post.slug), notice: t("flash.admin.posts.saved")
      else
        prepare_form(use_localized_content: false)
        render :new, status: :unprocessable_entity
      end
    end

    def update
      @post.assign_attributes(post_params)
      assign_tag_names

      if save_post
        redirect_to edit_admin_post_path(@post.slug), notice: t("flash.admin.posts.saved")
      else
        prepare_form(use_localized_content: false)
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @post.destroy
      redirect_to admin_posts_path, notice: t("flash.admin.posts.destroyed")
    end

    private

    def set_post
      @post = Post.find_by!(slug: params[:slug])
    end

    def post_params
      permitted = params.require(:post).permit(:title, :slug, :excerpt, :body, :category_id, :status, :published_at, :generate_audio)
      permitted[:status] = params[:commit_status] if Post.statuses.key?(params[:commit_status])
      permitted
    end

    def assign_tag_names
      @post.tag_names = params.dig(:post, :tag_names)
    end

    def save_post
      saved = T.let(false, T::Boolean)
      Post.transaction do
        saved = @post.save
        raise ActiveRecord::Rollback unless saved

        PostTranslationScheduler.call(post: @post, source_locale: I18n.locale)

        if @post.published?
          PostAudioScheduler.call(post: @post, locale: I18n.locale)
          target_locale = (PostTranslation::SUPPORTED_LOCALES - [ I18n.locale.to_s ]).first
          PostAudioScheduler.call(post: @post, locale: target_locale) if target_locale
        end
      end
      saved
    end

    def prepare_form(use_localized_content:)
      @categories = Category.ordered
      @form_content = if use_localized_content
        @post.localized_content
      else
        { title: @post[:title], body: @post[:body], excerpt: @post[:excerpt] }
      end
    end
  end
end
