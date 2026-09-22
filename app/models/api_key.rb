# typed: true

require "digest"
require "securerandom"

class ApiKey < ApplicationRecord
  belongs_to :admin_user

  enum :scope, { read: "read", write: "write" }

  validates :name, :key_digest, :key_prefix, :scope, presence: true
  validates :name, length: { maximum: 100 }
  validates :key_digest, uniqueness: true

  before_validation :normalize_name

  scope :ordered, -> { order(created_at: :desc) }

  def self.issue(admin_user:, name:, scope:)
    token = "tn_" + SecureRandom.base58(32)
    key = new(
      admin_user: admin_user,
      name: name,
      scope: scope,
      key_digest: Digest::SHA256.hexdigest(token),
      key_prefix: token[0, 8]
    )
    key.save!
    [ key, token ]
  end

  def self.find_active_by_token(token)
    return nil if token.blank?

    find_by(key_digest: Digest::SHA256.hexdigest(token), revoked_at: nil)
  end

  def active?
    revoked_at.nil?
  end

  def revoke!
    return if revoked_at.present?

    self.revoked_at = Time.current
    save!
  end

  def record_usage!
    update_column(:last_used_at, Time.current)
  end

  private

  def normalize_name
    self.name = name.to_s.strip
  end
end
