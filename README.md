# Tech Notes

[![CI](https://github.com/hiroeorz/tech_notes/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/hiroeorz/tech_notes/actions/workflows/ci.yml)

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

## 環境変数一覧

以下の変数をデプロイ実行環境（`kamal deploy` を実行するPC）で設定します。値はサンプルです。

### 最低限必要な環境変数

これだけ設定すれば `kamal deploy` でアプリが起動します。

```bash
# Docker Hub
export IMAGE="your-docker-user/tech_notes"
export KAMAL_REGISTRY_PASSWORD="your-docker-hub-token"

# デプロイ先サーバー
export SERVER_IP="192.168.0.1"
export PROXY_HOST="your-app.example.com"
export SSH_USER="deploy"

# アプリケーション
export RAILS_MASTER_KEY="$(cat config/master.key)"
export APP_HOST="your-app.example.com"

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

# Cloudflare R2（画像保存）— 画像アップロードを使用する場合のみ必須
export CLOUDFLARE_R2_ACCESS_KEY_ID="your-access-key"
export CLOUDFLARE_R2_SECRET_ACCESS_KEY="your-secret-key"
export CLOUDFLARE_R2_BUCKET="tech-notes-images"
export CLOUDFLARE_R2_ENDPOINT="https://<ACCOUNT_ID>.r2.cloudflarestorage.com"
export ACTIVE_STORAGE_PUBLIC_BASE_URL="https://cdn.example.com"

# Cloudflare Workers AI（記事要約生成）— 要約機能を使用する場合のみ必須
export CLOUDFLARE_ACCOUNT_ID="your-account-id"
export CLOUDFLARE_AI_API_TOKEN="your-api-token"
export CLOUDFLARE_AI_MODEL="@cf/meta/llama-3.2-1b-instruct"
export CLOUDFLARE_AI_TIMEOUT_SECONDS="60"

# Google Search Console — サイトマップ登録に使用
export GOOGLE_SITE_VERIFICATION="your-verification-token"

# Cloudflare Turnstile（bot検証）— コメント機能を使用する場合のみ必須
export TURNSTILE_SITE_KEY="0x4AAAAAAA-example"
export TURNSTILE_SECRET_KEY="0x4AAAAAAA-example-secret"

# Kamal デプロイ
export IMAGE="your-docker-user/tech_notes"
export SERVER_IP="192.168.0.1"
export PROXY_HOST="your-app.example.com"
export REGISTRY_USERNAME="your-docker-user"
export SSH_USER="deploy"
export KAMAL_REGISTRY_PASSWORD="your-docker-hub-token"
export RAILS_MASTER_KEY="$(cat config/master.key)"
```

## デプロイ・運用

- **デプロイアーキテクチャ**: `docs/deployment.md`
- **運用セットアップ手順**（R2 / バックアップ / Workers AI / Google Search Console）: `docs/manuals/operations.md`
- **バックアップ設計**: `docs/backup-requirements.md`
