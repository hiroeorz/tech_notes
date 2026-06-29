module Admin::PostImagesHelper
  def post_image_public_url(attachment)
    ActiveStoragePublicUrl.for(attachment)
  rescue ArgumentError
    nil
  end

  def post_image_markdown(attachment)
    url = post_image_public_url(attachment)
    return "" if url.blank?

    alt = File.basename(attachment.filename.to_s, File.extname(attachment.filename.to_s)).presence || "画像"
    "![#{alt}](#{url})"
  end

  def human_image_size(attachment)
    number_to_human_size(attachment.blob.byte_size)
  end
end
