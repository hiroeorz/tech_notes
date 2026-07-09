require "digest"

class Post < ApplicationRecord
  belongs_to :category
  belongs_to :admin_user
  has_many_attached :images
  has_many :post_tags, dependent: :destroy
  has_many :tags, through: :post_tags
  has_many :comments, dependent: :destroy

  IMAGE_CONTENT_TYPES = %w[image/jpeg image/png image/webp image/gif].freeze
  IMAGE_MAX_SIZE = 10.megabytes

  enum :status, { draft: 0, published: 1, reviewing: 2 }
  enum :kind, { article: 0, experiment: 1 }

  validates :title, :slug, :excerpt, :body, presence: true
  validates :slug, uniqueness: true
  validates :slug, format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/ }
  validates :reading_minutes, numericality: { greater_than: 0 }
  validate :validate_images

  before_validation :set_defaults
  before_validation :set_reading_minutes
  before_save :set_published_at

  scope :recent, -> { order(published_at: :desc, updated_at: :desc) }
  scope :publicly_visible, -> { published.where("published_at IS NULL OR published_at <= ?", Time.current) }

  def tag_names=(names)
    parsed_names = names.to_s.split(",").map(&:strip).reject(&:blank?).uniq
    self.tags = parsed_names.map do |name|
      Tag.find_or_create_by!(slug: slug_for_tag(name)) { |tag| tag.name = name }
    end
  end

  def tag_names
    tags.map(&:name).join(", ")
  end

  def display_date
    (published_at || created_at || Time.current).to_date
  end

  def body_preview
    if (img_match = body.to_s.match(/!\[([^\]]*)\]\(([^)]+)\)/))
      { type: :image, url: img_match[2], alt: img_match[1].presence || title }
    elsif (code_match = body.to_s.match(/```(\w*)\n(.+?)```/m))
      { type: :code, code: code_match[2].strip, language: code_match[1].presence || "text" }
    end
  end

  def to_param
    slug
  end

  def self.valid_image_upload?(upload)
    upload.present? &&
      upload.content_type.in?(IMAGE_CONTENT_TYPES) &&
      upload.size <= IMAGE_MAX_SIZE
  end

  private

  def validate_images
    images.each do |image|
      unless image.blob.content_type.in?(IMAGE_CONTENT_TYPES)
        errors.add(:images, :invalid_type)
      end

      next unless image.blob.byte_size > IMAGE_MAX_SIZE

      errors.add(:images, :too_large)
    end
  end

  def slug_for_tag(name)
    name.parameterize.presence || "tag-#{Digest::SHA1.hexdigest(name)[0, 10]}"
  end

  def set_defaults
    self.category ||= Category.ordered.first || Category.first
    if slug.blank?
      base_slug = title.present? ? title.parameterize : ""
      self.slug = base_slug.presence || "post-#{Time.current.to_i}"
    end
    if excerpt.blank? && body.present?
      clean_text = body.to_s.gsub(/[\r\n#`*_-]/, " ").squeeze(" ").strip
      self.excerpt = clean_text.truncate(140).presence || "要約なし"
    end
  end

  def set_reading_minutes
    self.reading_minutes = [ (body.to_s.length / 500.0).ceil, 1 ].max
  end

  def set_published_at
    self.published_at ||= Time.current if published? && published_at.blank?
  end
end
