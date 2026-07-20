# Tech Notes

[![CI](https://github.com/hiroeorz/tech_notes/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/hiroeorz/tech_notes/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

自分でサーバーを立てて運用する個人向けテックブログアプリケーション。

## スタック

- **フレームワーク**: Rails 8 (Ruby 4.0)
- **データベース**: PostgreSQL（開発・テストは SQLite）
- **画像ストレージ**: Cloudflare R2
- **フロントエンド**: importmap + Stimulus（Node.js 不要）
- **デプロイ**: Kamal（Docker コンテナ構成）

## 最小動作環境

- メモリ 1GB 以上の VM（1台で Rails + PostgreSQL を運用）
- OS: Ubuntu 24.04 以降
- 月額 700円〜（ConoHa 等の最安 VPS で可）

詳細は[個人ブログのための最小構成サーバー](https://hiroe-tech-notes.aomaro.com/posts/minimal-blog-server-configuration)を参照。

## サンプルサイト

[Tech Notes](https://hiroe-tech-notes.aomaro.com/)

## ローカル開発

```bash
git clone <this-repo>
cd tech_notes
rbenv install $(cat .ruby-version)
gem install bundler
bundle install
bin/rails db:prepare
bin/rails server
```

## テスト

```bash
bin/rails test                   # ユニット・統合テスト
bin/rails test:system            # ブラウザ駆動テスト
bin/rubocop                      # 静的解析
bin/brakeman --no-pager          # セキュリティスキャン
bin/bundler-audit                # Gem脆弱性チェック
```

## Codex サブエージェント

`.codex/agents/` には、作業内容に応じて親エージェントから起動するサブエージェントを定義しています。サブエージェントは担当範囲を越えて編集・コミット・プッシュ・PR操作を行いません。

| サブエージェント | 起動条件 | 主な担当 |
|---|---|---|
| `solution_architect` | 新機能・大きな仕様変更の実装前で、設計案、影響範囲、DB変更、互換性、チケット分割の検討が必要な場合 | 読み取り専用の設計補佐 |
| `bug_investigator` | 不具合の原因調査、再現確認、ログ・履歴・コード追跡が必要な場合 | 読み取り専用の不具合調査 |
| `rails_implementer` | モデル、コントローラー、サービス、ジョブ、ルーティング、Markdown処理などRailsバックエンドの実装チケットを委譲する場合 | Railsバックエンド実装 |
| `frontend_implementer` | ERB、CSS、Stimulus、アクセシビリティ、レスポンシブ表示など公開・管理画面のUI変更チケットを委譲する場合 | フロントエンド実装 |
| `test_engineer` | 回帰テスト、単体・統合・システムテストの設計・追加・失敗解析を委譲する場合 | Minitestのテスト実装・検証 |
| `database_reviewer` | マイグレーション、DB設計、インデックス、データ整合性、SQLite／PostgreSQL互換性のレビューが必要な場合 | 読み取り専用のDBレビュー |
| `code_reviewer` | 実装差分の独立レビュー、バグ、回帰、設計不整合、テスト不足の確認が必要な場合 | 読み取り専用のコードレビュー |
| `security_auditor` | 認証認可、入力処理、XSS、CSRF、SQLインジェクション、SSRF、アップロード、機密情報、依存脆弱性の監査が必要な場合 | 読み取り専用のセキュリティ監査 |
| `documentation_manager` | 実装・設定・テスト・運用の変更に伴い、仕様書、README、デプロイ・バックアップ文書の同期や監査が必要な場合 | コードを根拠にしたドキュメント管理 |
| `repository_operator` | 親エージェントが明示的にGit／GitHub操作を割り当てた場合 | Git状態確認、ステージング、コミット、プッシュ、PR操作 |
| `release_operator` | 親エージェントが明示的にデプロイ、ロールバック、DB変更、コンテナ操作、リリース確認、GitHub操作を割り当てた場合 | Kamalによるリリース・運用 |

特に、`repository_operator` と `release_operator` による外部状態の変更は明示割り当てを必須とします。コミット前には `security-check` を実行し、`git reset --hard`、`git clean`、force push、履歴書き換え、無断マージは実行しません。

## 環境変数一覧

以下の変数をデプロイ実行環境（`kamal deploy` を実行するPC）で設定します。値はサンプルです。

### 最低限必要な環境変数

これだけ設定すれば `kamal deploy` でアプリが起動します。

```bash
# Docker Hub等に作ったイメージへのパス
export IMAGE="your-docker-user/tech_notes"
export KAMAL_REGISTRY_PASSWORD="your-docker-hub-token"

# デプロイ先サーバー
export SERVER_IP="192.168.0.1"           # SSHでログインする先の本番サーバーIPアドレス
export SSH_USER="deploy"                 # SSHログインユーザー名

# アプリケーション
export RAILS_MASTER_KEY="$(cat config/master.key)"
export APP_HOST="your-app.example.com"   # デプロイ先ホスト名（SSL証明書・Railsホスト解決用）
export ADMIN_EMAIL="admin@example.com"
export ADMIN_PASSWORD="set-a-strong-unique-password"

# PostgreSQL
export POSTGRES_USER="postgres"
export POSTGRES_PASSWORD="your-password"
```

### 全環境変数一覧

すべてのカテゴリを含めた完全なリストです。最低限リストに含まれていない変数は、対応する機能を使う場合のみ必要です。

```bash
# PostgreSQL
export POSTGRES_USER="postgres"
export POSTGRES_PASSWORD="your-password"

# アプリケーション
export APP_HOST="your-app.example.com"
export ADMIN_EMAIL="admin@example.com"
export ADMIN_PASSWORD="set-a-strong-unique-password"

# Cloudflare R2（画像保存）— 画像アップロードを使用する場合のみ必須
export CLOUDFLARE_R2_ACCESS_KEY_ID="your-access-key"
export CLOUDFLARE_R2_SECRET_ACCESS_KEY="your-secret-key"
export CLOUDFLARE_R2_BUCKET="tech-notes-images"
export CLOUDFLARE_R2_ENDPOINT="https://<ACCOUNT_ID>.r2.cloudflarestorage.com"
export ACTIVE_STORAGE_PUBLIC_BASE_URL="https://cdn.example.com"

# Cloudflare Workers AI（記事要約生成・自動翻訳）— 要約・翻訳機能を使用する場合のみ必須
export CLOUDFLARE_ACCOUNT_ID="your-account-id"
export CLOUDFLARE_AI_API_TOKEN="your-api-token"
export CLOUDFLARE_AI_MODEL="@cf/meta/llama-3.2-1b-instruct"
export CLOUDFLARE_AI_TIMEOUT_SECONDS="60"
export CLOUDFLARE_AI_MAX_TOKENS="8192"   # 翻訳時の最大出力トークン数（長い記事は増やす）

# Google Cloud TTS（記事音声読み上げ）— 音声生成機能を使用する場合のみ必須
export GOOGLE_CLOUD_API_KEY="your-google-cloud-api-key"
export CLOUDFLARE_R2_AUDIO_BUCKET="tech-notes-audio"

# Google Search Console — サイトマップ登録に使用
export GOOGLE_SITE_VERIFICATION="your-verification-token"

# Cloudflare Turnstile（bot検証）— コメント機能を使用する場合のみ必須
export TURNSTILE_SITE_KEY="0x4AAAAAAA-example"
export TURNSTILE_SECRET_KEY="0x4AAAAAAA-example-secret"

# Resend（コメント通知メール）— コメント通知を使用する場合のみ必須
export RESEND_API_KEY="your-resend-api-key"
export MAILER_FROM_ADDRESS="no-reply@your-app.example.com"

# Kamal デプロイ
export IMAGE="your-docker-user/tech_notes"
export SERVER_IP="192.168.0.1"
export APP_HOST="your-app.example.com"
export REGISTRY_USERNAME="your-docker-user"
export SSH_USER="deploy"
export KAMAL_REGISTRY_PASSWORD="your-docker-hub-token"
export RAILS_MASTER_KEY="$(cat config/master.key)"
```

## デプロイ・運用

- **デプロイアーキテクチャ**: `docs/deployment.md`
- **運用セットアップ手順**（R2 / バックアップ / Workers AI / Google Search Console）: `docs/manuals/operations.md`
- **バックアップ設計**: `docs/backup-requirements.md`

## ライセンス

MIT License。詳細は [LICENSE](LICENSE) を参照。
