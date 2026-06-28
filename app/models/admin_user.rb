require "digest"

class AdminUser < ApplicationRecord
  has_many :posts, dependent: :restrict_with_exception

  validates :email, presence: true, uniqueness: true
  validates :password_digest, :password_salt, presence: true

  def self.digest_password(password, salt)
    Digest::SHA256.hexdigest("#{salt}--#{password}--#{Rails.application.secret_key_base}")
  end

  def password=(raw_password)
    self.password_salt = SecureRandom.hex(16)
    self.password_digest = self.class.digest_password(raw_password, password_salt)
  end

  def authenticate(raw_password)
    ActiveSupport::SecurityUtils.secure_compare(
      password_digest,
      self.class.digest_password(raw_password, password_salt)
    )
  end
end
