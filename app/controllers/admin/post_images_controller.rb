# typed: true

module Admin
  class PostImagesController < BaseController
    before_action :set_post

    def create
      upload = params[:image]

      unless ActiveStoragePublicUrl.configured?
        render json: { error: t("flash.admin.post_images.cdn_not_configured") }, status: :unprocessable_entity
        return
      end

      unless Post.valid_image_upload?(upload)
        render json: { error: image_upload_error(upload) }, status: :unprocessable_entity
        return
      end

      @post.images.attach(upload)
      attachment = @post.images.attachments.order(:created_at).last
      unless @post.valid?
        attachment&.purge
        render json: { error: @post.errors.full_messages.join(" / ") }, status: :unprocessable_entity
        return
      end

      render json: image_payload(attachment), status: :created
    rescue ArgumentError => error
      attachment&.purge
      render json: { error: error.message }, status: :unprocessable_entity
    end

    def destroy
      attachment = @post.images.attachments.find(params[:id])
      attachment.purge

      respond_to do |format|
        format.html { redirect_to edit_admin_post_path(@post.slug), notice: t("flash.admin.post_images.destroyed") }
        format.json { head :no_content }
      end
    end

    private

    def set_post
      @post = Post.find_by!(slug: params[:post_slug])
    end

    def image_payload(attachment)
      alt = alt_text(attachment.filename.to_s)
      url = ActiveStoragePublicUrl.for(attachment)

      {
        id: attachment.id,
        filename: attachment.filename.to_s,
        byte_size: attachment.blob.byte_size,
        content_type: attachment.blob.content_type,
        url: url,
        markdown: "![#{alt}](#{url})"
      }
    end

    def alt_text(filename)
      File.basename(filename, File.extname(filename)).presence || "画像"
    end

    def image_upload_error(upload)
      return t("flash.admin.post_images.no_file") if upload.blank?
      return t("flash.admin.post_images.invalid_type") unless upload.content_type.in?(Post::IMAGE_CONTENT_TYPES)
      return t("flash.admin.post_images.too_large") if upload.size > Post::IMAGE_MAX_SIZE

      t("flash.admin.post_images.upload_failed")
    end
  end
end
