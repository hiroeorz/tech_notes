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

      error = Post.upload_error(upload)
      unless error == :ok
        render json: { error: attachment_upload_error(error) }, status: :unprocessable_entity
        return
      end

      attachment_name = Post.attachment_kind(upload) == :document ? :documents : :images
      attach_and_respond(attachment_name, upload)
    end

    def destroy
      id = params[:id]
      raise ActiveRecord::RecordNotFound unless id.is_a?(String) && id.match?(/\A\d+\z/)

      attachment = @post.images.attachments.find_by(id: id) ||
        @post.documents.attachments.find_by(id: id)
      raise ActiveRecord::RecordNotFound unless attachment

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

    def attach_and_respond(attachment_name, upload)
      blob = ActiveStorage::Blob.create_and_upload!(
        io: upload,
        filename: upload.original_filename,
        content_type: upload.content_type
      )

      unless blob_matches_attachment_type?(attachment_name, blob)
        blob.purge
        render json: { error: t("flash.admin.post_attachments.invalid_type") }, status: :unprocessable_entity
        return
      end

      attachment = ActiveStorage::Attachment.create!(record: @post, blob: blob, name: attachment_name.to_s)
      unless helpers.post_attachment_public_url(attachment).present?
        attachment.purge
        render json: { error: t("flash.admin.post_attachments.upload_failed") }, status: :unprocessable_entity
        return
      end

      render json: attachment_payload(attachment), status: :created
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved, ActiveStorage::Error, ArgumentError => error
      blob&.purge
      Rails.logger.warn("Post attachment upload failed for post #{@post.id}: #{error.class}")
      render json: { error: t("flash.admin.post_attachments.upload_failed") }, status: :unprocessable_entity
    end

    def blob_matches_attachment_type?(attachment_name, blob)
      content_types = attachment_name == :documents ? Post::DOCUMENT_CONTENT_TYPES : Post::IMAGE_CONTENT_TYPES
      max_size = attachment_name == :documents ? Post::DOCUMENT_MAX_SIZE : Post::IMAGE_MAX_SIZE

      blob.content_type.in?(content_types) && blob.byte_size.positive? && blob.byte_size <= max_size
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

    def attachment_upload_error(error)
      t("flash.admin.post_attachments.#{error}")
    end
  end
end
