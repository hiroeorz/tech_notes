require "digest"

class Post < ApplicationRecord
  belongs_to :category
  belongs_to :admin_user
  has_many :post_tags, dependent: :destroy
  has_many :tags, through: :post_tags

  enum :status, { draft: 0, published: 1, reviewing: 2 }
  enum :kind, { article: 0, experiment: 1 }

  validates :title, :slug, :excerpt, :body, presence: true
  validates :slug, uniqueness: true
  validates :reading_minutes, numericality: { greater_than: 0 }

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

  def to_param
    slug
  end

  private

  def slug_for_tag(name)
    name.parameterize.presence || "tag-#{Digest::SHA1.hexdigest(name)[0, 10]}"
  end

  def set_reading_minutes
    self.reading_minutes = [ (body.to_s.length / 500.0).ceil, 1 ].max
  end

  def set_published_at
    self.published_at ||= Time.current if published? && published_at.blank?
  end
end
