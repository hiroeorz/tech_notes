# typed: true

class ActiveStoragePublicUrl
  def self.for(attachment_or_blob)
    new(attachment_or_blob).to_s
  end

  def self.for_key(key)
    base_url = configured_base_url
    raise ArgumentError, "public Active Storage base URL is not configured" if base_url.blank?

    normalized_key = key.to_s.sub(%r{\A/}, "")
    raise ArgumentError, "Active Storage key is blank" if normalized_key.blank?
    raise ArgumentError, "Invalid Active Storage key" if normalized_key.include?("..")

    "#{base_url}/#{normalized_key}"
  end

  def self.configured?
    configured_base_url.present?
  end

  def self.current_service?(attachment_or_blob)
    blob = attachment_or_blob.respond_to?(:blob) ? attachment_or_blob.blob : attachment_or_blob
    return false if blob.blank?

    blob.service_name.to_s == Rails.configuration.active_storage.service.to_s
  end

  def self.configured_base_url
    configured = ENV["ACTIVE_STORAGE_PUBLIC_BASE_URL"].presence ||
      Rails.application.credentials.dig(:active_storage, :public_base_url).presence
    configured.to_s.chomp("/")
  end

  def initialize(attachment_or_blob)
    @blob = attachment_or_blob.respond_to?(:blob) ? attachment_or_blob.blob : attachment_or_blob
  end

  def to_s
    self.class.for_key(@blob.key)
  end
end
