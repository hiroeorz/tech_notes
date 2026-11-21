# typed: true

module Admin
  class PostAttachmentsController < BaseController
    before_action :set_post

    def create
      upload = params[:attachment]

      unless ActiveStoragePublicUrl.configured?
        render json: { error: t("flash.admin.post_attachments.cdn_not_configured") }, status: :unprocessable_entity
        return
      end

      case Post.attachment_kind(upload)
      when :image
        attach_and_respond(@post.images, upload)
      when :document
        attach_and_respond(@post.documents, upload)
      else
        render json: { error: attachment_upload_error(upload) }, status: :unprocessable_entity
      end
    end

    def destroy
      attachment = @post.images.attachments.find_by(id: params[:id]) ||
        @post.documents.attachments.find(params[:id])
      attachment.purge

      respond_to do |format|
        format.html { redirect_to edit_admin_post_path(@post.slug), notice: t("flash.admin.post_attachments.destroyed") }
        format.json { head :no_content }
      end
    end

    private

    def set_post
      @post = Post.find_by!(slug: params[:post_slug])
    end

    def attach_and_respond(collection, upload)
      collection.attach(upload)
      attachment = collection.attachments.order(id: :desc).first
      unless attachment
        render json: { error: t("flash.admin.post_attachments.upload_failed") }, status: :unprocessable_entity
        return
      end
      unless @post.valid?
        attachment.purge
        render json: { error: @post.errors.full_messages.join(" / ") }, status: :unprocessable_entity
        return
      end

      render json: attachment_payload(attachment), status: :created
    rescue ArgumentError => error
      attachment&.purge
      render json: { error: error.message }, status: :unprocessable_entity
    end

    def attachment_payload(attachment)
      url = helpers.post_attachment_public_url(attachment)

      {
        id: attachment.id,
        filename: attachment.filename.to_s,
        byte_size: attachment.blob.byte_size,
        content_type: attachment.blob.content_type,
        kind: attachment.blob.content_type.in?(Post::DOCUMENT_CONTENT_TYPES) ? "document" : "image",
        url: url,
        markdown: helpers.post_attachment_markdown(attachment)
      }
    end

    def attachment_upload_error(upload)
      return t("flash.admin.post_attachments.no_file") if upload.blank?
      return t("flash.admin.post_attachments.invalid_type") unless upload.respond_to?(:content_type) && upload.respond_to?(:size)

      if upload.content_type.in?(Post::IMAGE_CONTENT_TYPES)
        return t("flash.admin.post_attachments.image_too_large") if upload.size > Post::IMAGE_MAX_SIZE
      elsif upload.content_type.in?(Post::DOCUMENT_CONTENT_TYPES)
        return t("flash.admin.post_attachments.document_too_large") if upload.size > Post::DOCUMENT_MAX_SIZE
      else
        return t("flash.admin.post_attachments.invalid_type")
      end

      t("flash.admin.post_attachments.upload_failed")
    end
  end
end
