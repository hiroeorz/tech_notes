class SiteSetting < ApplicationRecord
  has_one_attached :ogp_image
  has_one_attached :profile_image

  validates :blog_title, :tagline, :site_url, :description, :profile_name, :profile_title, :profile_bio, presence: true
  validate :validate_ogp_image
  validate :validate_profile_image

  def self.current
    first_or_create!(
      description: "インフラ、クラウド、SRE、自動化などに関する学びや実践を記録する個人のテックブログです。",
      profile_bio: "クラウドや自動化が好きで、日々の業務や個人の実験で得た学びを発信しています。",
      github_url: "https://github.com/hiroe-tech",
      x_url: "https://x.com/hiroe_tech",
      rss_url: "https://hiroe-tech-notes.dev/feed.xml",
      zenn_url: "https://zenn.dev/hiroe_tech",
      note_url: "https://note.com/hiroe_tech"
    )
  end

  private

  def validate_ogp_image
    validate_image_attachment(ogp_image, label: "OGP画像", max_size: 2.megabytes)
  end

  def validate_profile_image
    validate_image_attachment(profile_image, label: "プロフィール画像", max_size: 1.megabyte)
  end

  def validate_image_attachment(attachment, label:, max_size:)
    return unless attachment.attached?

    unless attachment.blob.content_type.in?(%w[image/jpeg image/png])
      errors.add(attachment.name, "#{label}はJPGまたはPNGでアップロードしてください。")
    end

    return unless attachment.blob.byte_size > max_size

    errors.add(attachment.name, "#{label}は#{max_size / 1.megabyte}MB以下でアップロードしてください。")
  end
end
