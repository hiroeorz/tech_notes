module Admin::PostAttachmentsHelper
  def post_attachment_public_url(attachment)
    return unless ActiveStoragePublicUrl.configured?
    return unless ActiveStoragePublicUrl.current_service?(attachment)

    ActiveStoragePublicUrl.for(attachment)
  rescue ArgumentError
    nil
  end

  def post_attachment_markdown(attachment)
    url = post_attachment_public_url(attachment)
    return "" if url.blank?

    if document_attachment?(attachment)
      "[#{escape_markdown_link_text(attachment.filename.to_s)}](#{url})"
    else
      alt = File.basename(attachment.filename.to_s, File.extname(attachment.filename.to_s)).presence ||
        t("admin.posts.form.image_alt_default")
      "![#{escape_markdown_link_text(alt)}](#{url})"
    end
  end

  def document_attachment?(attachment)
    attachment.blob.content_type.in?(Post::DOCUMENT_CONTENT_TYPES)
  end

  def human_attachment_size(attachment)
    number_to_human_size(attachment.blob.byte_size)
  end

  private

  def escape_markdown_link_text(text)
    text.to_s.squish.gsub(/([\\`*_\[\]<>])/) { "\\#{$1}" }
  end
end
