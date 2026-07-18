# typed: true

class Category < ApplicationRecord
  has_many :posts, dependent: :restrict_with_exception

  validates :name, :slug, presence: true
  validates :slug, uniqueness: true
  validates :slug, format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/ }

  scope :ordered, -> { order(:position, :name) }

  def localized_name
    if I18n.locale == :ja || name_en.blank?
      name
    else
      name_en
    end
  end
end
