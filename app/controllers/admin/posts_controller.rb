module Admin
  class PostsController < BaseController
    before_action :set_post, only: [ :show, :preview, :edit, :update, :destroy ]

    def index
      @posts = Post.includes(:category, :tags).recent
      @posts = @posts.where("LOWER(posts.title) LIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(params[:q].downcase)}%") if params[:q].present?
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
      @page_title = "プレビュー: #{@post.title} | #{current_site_setting.blog_title}"
      @page_description = @post.excerpt
      @page_type = "article"
      @page_url = preview_admin_post_url(@post.slug)
      @toc = helpers.extract_headings(@post.body)
      @related_posts = Post.where(category: @post.category).where.not(id: @post.id).recent.limit(3)
      render "posts/show"
    end

    def markdown_preview
      render html: MarkdownRenderer.new(params[:body].to_s).render.html_safe, layout: false
    end

    def new
      @post = Post.new(status: :draft, kind: :article, published_at: Time.current)
      @categories = Category.ordered
    end

    def edit
      @categories = Category.ordered
    end

    def create
      @post = current_admin_user.posts.new(post_params)
      assign_tag_names

      if @post.save
        redirect_to edit_admin_post_path(@post.slug), notice: "記事を保存しました。"
      else
        @categories = Category.ordered
        render :new, status: :unprocessable_entity
      end
    end

    def update
      @post.assign_attributes(post_params)
      assign_tag_names

      if @post.save
        redirect_to edit_admin_post_path(@post.slug), notice: "記事を保存しました。"
      else
        @categories = Category.ordered
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @post.destroy
      redirect_to admin_posts_path, notice: "記事を削除しました。"
    end

    private

    def set_post
      @post = Post.find_by!(slug: params[:slug])
    end

    def post_params
      permitted = params.require(:post).permit(:title, :slug, :excerpt, :body, :category_id, :status, :kind, :published_at)
      permitted[:status] = params[:commit_status] if Post.statuses.key?(params[:commit_status])
      permitted
    end

    def assign_tag_names
      @post.tag_names = params.dig(:post, :tag_names)
    end
  end
end
