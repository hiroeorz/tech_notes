require "securerandom"

setting = SiteSetting.current
setting.update!(
  blog_title: "Hiroe Tech Notes",
  tagline: "あるエンジニアの技術ノート",
  site_url: "https://#{ENV.fetch('APP_HOST', 'example.com')}",
  description: "インフラ、クラウド、SRE、自動化などに関する学びや実践を記録する個人のテックブログです。実際の構築手順やトラブルシューティング、ツールの使い方、実験ログなどをわかりやすく共有しています。",
  profile_name: "Hiroe",
  profile_title: "インフラエンジニア / プログラマ",
  profile_title_en: "Infrastructure Engineer / Programmer",
  profile_email: ENV.fetch("PROFILE_EMAIL", "admin@example.com"),
  profile_bio: "クラウドや自動化が好きで、日々の業務や個人の実験で得た学びを発信しています。",
  profile_bio_en: "I love cloud computing and automation. I share what I learn from daily work and personal experiments.",
  github_url: ENV.fetch("PROFILE_GITHUB_URL", "https://example.com/github"),
  x_url: ENV.fetch("PROFILE_X_URL", "https://example.com/x"),
  rss_url: ENV.fetch("PROFILE_RSS_URL", "https://example.com/feed.xml"),
  zenn_url: ENV.fetch("PROFILE_ZENN_URL", "https://example.com/zenn"),
  note_url: ENV.fetch("PROFILE_NOTE_URL", "https://example.com/note"),
  posts_per_page: 10
)

admin_email = ENV["ADMIN_EMAIL"]
admin_password = ENV["ADMIN_PASSWORD"]
if Rails.env.production? || admin_email.present? || admin_password.present?
  raise "ADMIN_EMAIL and ADMIN_PASSWORD must both be set" if admin_email.blank? || admin_password.blank?
else
  admin_email = "admin@example.com"
  admin_password = SecureRandom.base64(48)
end

admin = AdminUser.find_or_initialize_by(email: admin_email)
admin.password = admin_password if admin.new_record?
admin.save!

categories = [
  [ "インフラ", "Infrastructure", "infrastructure", "cloud", 1 ],
  [ "AWS", "AWS", "aws", "aws", 2 ],
  [ "Azure", "Azure", "azure", "azure", 3 ],
  [ "自動化", "Automation", "automation", "automation", 4 ],
  [ "プログラミング", "Programming", "programming", "code", 5 ],
  [ "セキュリティ", "Security", "security", "security", 6 ],
  [ "AI開発", "AI Development", "ai-development", "code", 7 ],
  [ "運用", "Operations", "operations", "ops", 8 ],
  [ "ポエム", "Poem", "poem", "poem", 9 ]
].to_h { |name, name_en, slug, icon, position|
  category = Category.find_or_create_by!(slug: slug) do |record|
    record.name = name
    record.name_en = name_en
    record.icon_key = icon
    record.position = position
  end
  category.update!(name: name, name_en: name_en, icon_key: icon, position: position)
  [ slug, category ]
}

def upsert_post(admin:, category:, attrs:, tags:)
  post = Post.find_or_initialize_by(slug: attrs[:slug])
  post.assign_attributes(attrs.merge(category: category, admin_user: admin))
  post.tag_names = tags.join(", ")
  post.save!
  post
end

body_remote_state = <<~MARKDOWN
  # Terraformのリモートステート設計と運用のベストプラクティス

  Terraformでチーム開発や複数環境の管理を行う上で欠かせない「リモートステート」について、S3とDynamoDBを使った構成例や `backend.tf` の設定、運用上の注意点まで、実務で役立つベストプラクティスをまとめました。

  ## この記事でわかること
  - リモートステートを採用するメリットと基本構成
  - S3 + DynamoDB を使った安全な構成例と設定方法
  - 運用時に気をつけたいポイントやベストプラクティス

  ## なぜリモートステートが必要なのか
  Terraformのデフォルトはローカルステートです。これは単一ユーザーでの利用には十分ですが、チームでの共有やCI/CDでの利用には不向きです。リモートステートを利用することで、ステートの一元管理・共有・ロック制御が可能になり、衝突や破損のリスクを大きく減らせます。

  > ステートファイルはインフラの真実のソースです。可用性・整合性・セキュリティを最優先で設計しましょう。

  ## 構成例
  ![リモートステート構成図](images/remote-state-architecture.png)

  ## backend.tf の例
  ```hcl
  terraform {
    backend "s3" {
      bucket         = "hiroe-tfstate-prod"
      key            = "network/terraform.tfstate"
      region         = "ap-northeast-1"
      dynamodb_table = "terraform-locks"
      encrypt        = true
    }
  }
  ```

  ## 運用上の注意点
  - バージョニングを有効化し、履歴を保全する
  - バケットポリシーやKMSでアクセスを最小権限に制御する
  - DynamoDBのロック設定で同時実行のリスクを軽減する
  - ステートのバックアップとリストア手順をドキュメント化する
  - ブランチや環境ごとにステートを分離する設計にする

  ## まとめ
  リモートステートはTerraform運用の土台です。S3 + DynamoDBの構成はシンプルで拡張性が高く、多くの現場で採用されています。設計時から可用性・セキュリティ・運用性を意識し、チームで安全にインフラ管理を進めましょう。
MARKDOWN

posts = [
  {
    attrs: {
      title: "Terraformのリモートステート設計と運用のベストプラクティス",
      slug: "terraform-remote-state-best-practices",
      excerpt: "Terraformでチーム開発や複数環境の管理を行う上で欠かせないリモートステートについて、S3とDynamoDBを使った構成例や運用上の注意点をまとめました。",
      body: body_remote_state,
      status: :published,
      kind: :article,
      published_at: Time.zone.parse("2025-05-21 10:00")
    },
    category: categories["infrastructure"],
    tags: [ "Terraform", "IaC", "AWS", "S3", "DynamoDB", "Infrastructure as Code" ]
  },
  {
    attrs: {
      title: "AWS Control Towerを試して理解したマルチアカウント管理の考え方",
      slug: "aws-control-tower-multi-account",
      excerpt: "AWS Control Towerを使い、組織単位とガードレールの考え方を整理しました。",
      body: "## はじめに\nAWS Control Towerでマルチアカウント管理を試しました。\n\n## わかったこと\n- 組織単位の設計が重要\n- 最小権限の運用ルールを先に決める\n- 監査用アカウントを分離する",
      status: :published,
      kind: :article,
      published_at: Time.zone.parse("2025-05-18 09:00")
    },
    category: categories["aws"],
    tags: [ "AWS", "インフラ" ]
  },
  {
    attrs: {
      title: "Terraformのfor_eachとcountの使い分けを整理してみた",
      slug: "terraform-for-each-count",
      excerpt: "Terraformで複数リソースを扱うときに迷いやすいfor_eachとcountの選び方を整理しました。",
      body: "## 判断基準\n安定したキーを持つ集合は `for_each`、単純な個数指定は `count` が扱いやすいです。",
      status: :published,
      kind: :article,
      published_at: Time.zone.parse("2025-05-14 09:00")
    },
    category: categories["infrastructure"],
    tags: [ "Terraform", "IaC" ]
  },
  {
    attrs: {
      title: "GitHub ActionsでTerraformを自動実行するワークフロー",
      slug: "github-actions-terraform-workflow",
      excerpt: "Terraform plan/applyをGitHub Actionsで安全に実行するための構成をまとめました。",
      body: "## ワークフロー\nPull Requestではplan、mainへのmergeでapplyする構成を基本にしました。",
      status: :published,
      kind: :article,
      published_at: Time.zone.parse("2025-05-10 09:00")
    },
    category: categories["automation"],
    tags: [ "GitHub Actions", "Terraform", "自動化" ]
  },
  {
    attrs: {
      title: "AWS S3のアクセスログをAthenaで分析してみる",
      slug: "s3-access-log-athena",
      excerpt: "S3アクセスログをAthenaで集計し、アクセス傾向を調べました。",
      body: "## 検証\nS3アクセスログをGlue Data Catalogに登録し、Athenaでクエリしました。",
      status: :published,
      kind: :article,
      published_at: Time.zone.parse("2025-05-06 09:00")
    },
    category: categories["aws"],
    tags: [ "AWS", "分析" ]
  },
  {
    attrs: {
      title: "Linuxのログローテーションを自作スクリプトでやってみた",
      slug: "linux-log-rotation-script",
      excerpt: "logrotateを参考に、ログローテーションの基本処理をシェルで実装しました。",
      body: "## 実装\n日付付きファイルへの退避、圧縮、世代管理を順番に実装しました。",
      status: :published,
      kind: :article,
      published_at: Time.zone.parse("2025-05-01 09:00")
    },
    category: categories["operations"],
    tags: [ "Linux", "運用" ]
  },
  {
    attrs: {
      title: "Kubernetesの基本アーキテクチャと主要コンポーネント",
      slug: "kubernetes-basic-architecture",
      excerpt: "Kubernetesを学ぶ上で押さえておきたいコンポーネントの役割を整理しました。",
      body: "## コンポーネント\nControl PlaneとWorker Nodeの役割を分けて考えると理解しやすいです。",
      status: :reviewing,
      kind: :article,
      published_at: nil
    },
    category: categories["infrastructure"],
    tags: [ "Kubernetes", "コンテナ", "アーキテクチャ" ]
  },
  {
    attrs: {
      title: "Linuxでプロセスとリソースを効率的に管理する方法",
      slug: "linux-process-resource-management",
      excerpt: "topやhtop、systemd、ulimitなどを使ってサーバーの安定運用に必要な基本をまとめました。",
      body: "## 基本\nプロセス状態とリソース制限を見ながら、異常時の切り分けを行います。",
      status: :draft,
      kind: :article,
      published_at: nil
    },
    category: categories["operations"],
    tags: [ "Linux", "運用", "パフォーマンス" ]
  }
]

posts.each do |entry|
  upsert_post(admin: admin, category: entry[:category], attrs: entry[:attrs], tags: entry[:tags])
end

experiments = [
  [ "Cloudflare Tunnelを使って自宅サーバーを安全に公開する", "cloudflare-tunnel-home-server", "Argo Tunnelでローカル環境を公開。設定のつまずきどころとハマりポイントを整理。", categories["infrastructure"], [ "networking" ], "2025-05-19" ],
  [ "Ansibleで複数サーバーに共通設定を適用してみる", "ansible-common-server-settings", "Playbookのベストプラクティスを意識しつつ、冪等性の大切さを再確認。", categories["automation"], [ "ansible" ], "2025-05-13" ],
  [ "Amazon SQSの可視性タイムアウトを調整してみた", "sqs-visibility-timeout", "処理時間が長いワーカーでの再試行問題を可視性タイムアウトで解決。", categories["aws"], [ "aws" ], "2025-05-07" ]
]

experiments.each do |title, slug, excerpt, category, tags, date|
  upsert_post(
    admin: admin,
    category: category,
    tags: tags,
    attrs: {
      title: title,
      slug: slug,
      excerpt: excerpt,
      body: "## 実験メモ\n#{excerpt}\n\n## 結果\n小さく試すことで、運用時に気をつける点が見えてきました。",
      status: :published,
      kind: :experiment,
      published_at: Time.zone.parse("#{date} 09:00")
    }
  )
end

puts "Seeded #{Category.count} categories, #{Tag.count} tags, #{Post.count} posts."
