class Category < ApplicationRecord
  has_many :posts, dependent: :restrict_with_exception

  validates :name, :slug, presence: true
  validates :slug, uniqueness: true

  scope :ordered, -> { order(:position, :name) }
end
