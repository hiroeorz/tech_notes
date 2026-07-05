module Admin
  class CommentsController < BaseController
    def index
      @comments = Comment.includes(:post).recent
      current_admin_user.touch(:last_comments_read_at)
    end

    def destroy
      @comment = Comment.find(params[:id])
      @comment.destroy!
      redirect_to admin_comments_path, notice: "コメントを削除しました。"
    end
  end
end
