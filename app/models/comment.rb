class Comment < ApplicationRecord
  belongs_to :post

  AUTHOR_NAME_MAX = 30
  BODY_MAX = 1000

  validates :author_name, presence: true, length: { maximum: AUTHOR_NAME_MAX }
  validates :body, presence: true, length: { maximum: BODY_MAX }

  before_save :sanitize_fields

  scope :recent, -> { order(created_at: :desc) }
  scope :oldest, -> { order(created_at: :asc) }

  def display_body
    ERB::Util.html_escape(body).gsub(/\r?\n/, "<br>").html_safe
  end

  private

  def sanitize_fields
    self.author_name = author_name.to_s.strip
    self.body = body.to_s.strip.tr("\u0000", "")
    self.ip_address = ip_address.to_s.presence
  end
end
