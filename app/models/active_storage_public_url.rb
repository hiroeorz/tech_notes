class ActiveStoragePublicUrl
  def self.for(attachment_or_blob)
    new(attachment_or_blob).to_s
  end

  def self.configured?
    configured_base_url.present?
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
    raise ArgumentError, "public Active Storage base URL is not configured" if public_base_url.blank?

    "#{public_base_url}/#{@blob.key}"
  end

  private

  def public_base_url
    @public_base_url ||= self.class.configured_base_url
  end
end
