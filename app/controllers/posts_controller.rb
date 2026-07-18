# typed: true

class PostsController < ApplicationController
  def index
    @kind = params[:kind].presence || "article"
    @posts = Post.publicly_visible.includes(:category, :tags, :post_translations).recent
    @posts = @posts.where(kind: Post.kinds[@kind]) if Post.kinds.key?(@kind)
    @posts = @posts.joins(:category).where(categories: { slug: params[:category] }) if params[:category].present?
    @posts = @posts.joins(:tags).where(tags: { slug: params[:tag] }) if params[:tag].present?
    @posts = T.unsafe(@posts).search_by_title(params[:q], locale: I18n.locale) if params[:q].present?
    if (month = parsed_month)
      @posts = @posts.where(published_at: month.beginning_of_month..month.end_of_month)
    end
    @posts = ordered_posts(@posts)
    @page = [ params[:page].to_i, 1 ].max
    @per_page = current_site_setting.posts_per_page
    @total_count = @posts.count
    @total_pages = [ (@total_count / @per_page.to_f).ceil, 1 ].max
    @page = [ @page, @total_pages ].min
    @posts = @posts.limit(@per_page).offset((@page - 1) * @per_page)
    @categories = Category.ordered
    @tags = Tag.ordered
    load_sidebar
  end

  def show
    @post = Post.publicly_visible.includes(:category, :tags, :post_translations, :post_audios).find_by!(slug: params[:slug])
    @post.increment!(:views_count) unless admin_signed_in?
    @comment = @post.comments.build
    @comments = @post.comments.oldest
    set_post_meta(@post)
    @related_posts = Post.publicly_visible.includes(:post_translations).where(category: @post.category).where.not(id: @post.id).recent.limit(3)
    @toc = helpers.extract_headings(@post.localized_body)
    load_sidebar
  end

  def tags
    tag_counts = PostTag.joins(:post).merge(Post.publicly_visible).group(:tag_id).count
    @tags = Tag.ordered.select { |tag| tag_counts.key?(tag.id) }
    @tags.each do |tag|
      tag.define_singleton_method(:posts_count) { tag_counts.fetch(tag.id, 0) }
    end
  end

  def categories
    category_counts = Post.publicly_visible.group(:category_id).count
    @categories = Category.ordered.select { |category| category_counts.key?(category.id) }
    @categories.each do |category|
      category.define_singleton_method(:posts_count) { category_counts.fetch(category.id, 0) }
    end
  end

  def archives
    @archive_groups = Post.publicly_visible.includes(:category, :tags, :post_translations).recent.group_by { |post| post.display_date.beginning_of_month }
    load_sidebar
  end

  def feed
    @posts = Post.publicly_visible.includes(:category, :tags, :post_translations).recent.limit(20)
    respond_to do |format|
      format.xml
    end
  end

  private

  def parsed_month
    return if params[:month].blank?

    Date.strptime(params[:month], "%Y-%m")
  rescue Date::Error
    nil
  end

  def ordered_posts(posts)
    case params[:sort]
    when "oldest"
      posts.reorder(published_at: :asc, updated_at: :asc)
    when "updated"
      posts.reorder(updated_at: :desc)
    else
      posts
    end
  end

  def set_post_meta(post)
    @page_title = "#{post.localized_title} | #{current_site_setting.blog_title}"
    @page_description = post.localized_excerpt
    @page_type = "article"
    @page_url = post_url(post.slug)
  end
end
