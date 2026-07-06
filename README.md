# Tech Notes

[![CI](https://github.com/hiroeorz/tech_notes/actions/workflows/ci.yml/badge.svg)](https://github.com/hiroeorz/tech_notes/actions/workflows/ci.yml)

個人のテックブログアプリケーション（Rails 8 + PostgreSQL + Cloudflare R2）。

## 環境変数一覧

以下の全変数を bash にコピペして利用できます。値はサンプルです。
注）以下の環境変数はサーバー上ではなく、`./bin/kamal deploy` を実行するPCで設定してください。

```bash
# ============================================
# PostgreSQL 接続（デフォルト値があるため変更時のみ設定）
# ============================================
# export DB_HOST="tech_notes-db"                          # ホスト (デフォルト: 127.0.0.1)
# export DB_PORT="5432"                                   # ポート (デフォルト: 5432)
export POSTGRES_USER="postgres"                           # ユーザー名
export POSTGRES_PASSWORD="your-password"                  # パスワード
# export POSTGRES_DB="tech_notes_production"              # プライマリDB名
# export POSTGRES_DB_CACHE="tech_notes_production_cache"  # Solid Cache用DB
# export POSTGRES_DB_QUEUE="tech_notes_production_queue"  # Solid Queue用DB
# export POSTGRES_DB_CABLE="tech_notes_production_cable"  # Solid Cable用DB

# ============================================
# アプリケーション
# ============================================
export APP_HOST="your-app.example.com"              # 本番ホスト名（production必須）
# export RAILS_MAX_THREADS="5"                      # Pumaスレッド数 / DBプールサイズ (デフォルト: 3)
# export PORT="3000"                                # Pumaリスンポート (デフォルト: 3000)
# export RAILS_LOG_LEVEL="info"                     # ログレベル (デフォルト: info)
# export ACTIVE_STORAGE_SERVICE="cloudflare_r2"     # 開発環境のストレージ (デフォルト: cloudflare_r2)
# export SOLID_QUEUE_IN_PUMA="true"                 # Puma内でSolid Queueを起動
# export JOB_CONCURRENCY="1"                        # Solid Queueワーカー数 (デフォルト: 1)

# ============================================
# Cloudflare R2 (Active Storage 画像保存)
# ============================================
export CLOUDFLARE_R2_ACCESS_KEY_ID="your-access-key"
export CLOUDFLARE_R2_SECRET_ACCESS_KEY="your-secret-key"
export CLOUDFLARE_R2_BUCKET="tech-notes-images"
export CLOUDFLARE_R2_ENDPOINT="https://<ACCOUNT_ID>.r2.cloudflarestorage.com"
export ACTIVE_STORAGE_PUBLIC_BASE_URL="https://cdn.example.com"

# ============================================
# Cloudflare Workers AI (記事要約生成)
# ============================================
export CLOUDFLARE_ACCOUNT_ID="your-account-id"
export CLOUDFLARE_AI_API_TOKEN="your-api-token"
export CLOUDFLARE_AI_MODEL="@cf/meta/llama-3.2-1b-instruct"
export CLOUDFLARE_AI_TIMEOUT_SECONDS="60"

# ============================================
# Google Search Console (サイト所有権確認)
# ============================================
export GOOGLE_SITE_VERIFICATION="your-verification-token"

# ============================================
# Cloudflare Turnstile (bot検証: コメント・管理者ログイン)
# ============================================
export TURNSTILE_SITE_KEY="0x4AAAAAAA-example"
export TURNSTILE_SECRET_KEY="0x4AAAAAAA-example-secret"

# ============================================
# Kamal デプロイ用 (デプロイ実行環境でのみ必要)
# ============================================
export IMAGE="your-docker-user/tech_notes"               # Dockerイメージ名
export SERVER_IP="192.168.0.1"                          # デプロイ先サーバーIP
export PROXY_HOST="your-app.example.com"          # SSLプロキシホスト名
export REGISTRY_USERNAME="your-docker-user"              # Docker Hubユーザー名
export SSH_USER="deploy"                                # SSH接続ユーザー
export KAMAL_REGISTRY_PASSWORD="your-docker-hub-token"  # Docker Hubアクセストークン
export RAILS_MASTER_KEY="$(cat config/master.key)"      # credentials復号キー
```

> **補足**: `POSTGRES_PASSWORD` / Cloudflare 関連の一部変数は `config/credentials.yml.enc` からのフォールバックを持ちます。上記でコメントアウトした変数は全てコード内にデフォルト値が定義されており、未設定でもアプリは動作します。

---

## Cloudflare R2 画像ストレージ

このアプリケーションは Active Storage を使ってアップロード画像を Cloudflare R2 に保存します。
記事画像は Markdown 内で公開 CDN URL として挿入されます。

### バケット名

`CLOUDFLARE_R2_BUCKET` には既存の R2 バケット名を設定します。

Cloudflare ダッシュボードで:

1. `R2 Object Storage` を開く
2. `Buckets` を開く
3. バケット名をコピーする

### アクセスキーとシークレット

`CLOUDFLARE_R2_ACCESS_KEY_ID` と `CLOUDFLARE_R2_SECRET_ACCESS_KEY` 用の R2 API トークンを作成します。

Cloudflare ダッシュボードで:

1. `R2 Object Storage` を開く
2. R2 アカウント詳細領域から API トークン管理画面を開く
3. アカウントまたはユーザー API トークンを作成する
4. 対象バケットへのオブジェクト読み書き権限を付与する
5. 生成された `Access Key ID` と `Secret Access Key` をコピーする

シークレットアクセスキーはトークン作成時にのみ表示されます。すぐに保存してください。

### R2 エンドポイント

`CLOUDFLARE_R2_ENDPOINT` は Cloudflare アカウント ID から設定します。

EU 管轄のバケットの場合は EU 固有のエンドポイントを使用します:

```text
https://<ACCOUNT_ID>.eu.r2.cloudflarestorage.com
```

アカウント ID は Cloudflare ダッシュボードのアカウント概要で確認できます。

### 公開 CDN URL

`ACTIVE_STORAGE_PUBLIC_BASE_URL` は R2 オブジェクト配信に使用する公開 CDN URL を設定します。R2 バケットにカスタムドメインを設定することを推奨します。

Cloudflare ダッシュボードで:

1. `R2 Object Storage` を開く
2. 対象バケットを開く
3. `Settings` を開く
4. `Custom Domains` でドメインを追加する
5. ドメインステータスがアクティブになるまで待つ

CDN URL は Active Storage の blob key でオブジェクトを提供する必要があります。例えば blob key が `abc123` の場合、以下の URL で画像が返される必要があります:

```text
https://cdn.example.com/abc123
```

## PostgreSQL バックアップ準備

本番環境の PostgreSQL バックアップは VM ホスト上の cron で実行されます。
バックアップスクリプトは `docs/backup-requirements.md` に記載されており、ダンプファイルを `rclone copyto` で Cloudflare R2 にアップロードします。

バックアップバケット:

```text
your-project-backup
```

### Cloudflare R2 セットアップ

Cloudflare ダッシュボードで:

1. `R2 Object Storage` を開く
2. `your-project-backup` バケットを作成または開く
3. バケット用の R2 API トークンまたはアクセスキーを作成する
4. `your-project-backup` へのオブジェクト読み書き権限を付与する
5. 生成された `Access Key ID` と `Secret Access Key` をコピーする

画像バケットのキーを流用せず、バックアップ専用のキーを使用してください。画像バケットのみにアクセスできるキーでは `your-project-backup` への書き込み時に `403 Forbidden` が発生します。

### VM rclone セットアップ

VM ホストに `rclone` をインストール:

```bash
sudo apt update
sudo apt install -y rclone
rclone version
```

cron を実行するユーザーで `r2` リモートを設定します。本番 VM ではデプロイユーザーを使用します。

```bash
rclone config
```

以下の値を設定:

```text
name = r2
type = s3
provider = Cloudflare
region = auto
endpoint = https://<ACCOUNT_ID>.r2.cloudflarestorage.com
acl = private
no_check_bucket = true
```

`access_key_id` と `secret_access_key` には Cloudflare で作成したバックアップバケット用のキーを設定します。

設定ファイルの場所を確認:

```bash
rclone config file
```

デプロイユーザーの場合、通常は以下の場所:

```text
~/.config/rclone/rclone.conf
```

### R2 書き込みテスト

`copyto` でアップロードをテストします。このバックアップフローでは `rclone rcat` を使用しないでください（ストリーミングアップロードは R2 で `501 NotImplemented` になる可能性があります）。

```bash
tmp=$(mktemp)
echo "test $(date)" > "$tmp"

rclone copyto "$tmp" r2:your-project-backup/postgresql/rclone_test.txt --s3-no-check-bucket
rclone cat r2:your-project-backup/postgresql/rclone_test.txt --s3-no-check-bucket
rclone deletefile r2:your-project-backup/postgresql/rclone_test.txt --s3-no-check-bucket

rm "$tmp"
```

アップロードが `403 Forbidden` で失敗する場合は、`your-project-backup` へのオブジェクト読み書き権限を持つ R2 アクセスキーを再作成してください。

### VM cron 準備

スクリプト保存先ディレクトリを作成:

```bash
mkdir -p ~/ops
chmod 750 ~/ops
```

バッククログファイルを作成:

```bash
sudo touch /var/log/tech_notes_backup.log
sudo chown $USER:$USER /var/log/tech_notes_backup.log
chmod 640 /var/log/tech_notes_backup.log
```

Kamal PostgreSQL accessory コンテナが表示されることを確認:

```bash
docker ps --filter label=service=tech_notes-db --format '{{.Names}}'
```

`script/ops/backup_postgres_to_r2.sh` が `~/ops/backup_postgres_to_r2.sh` にデプロイされた後、デプロイユーザーで cron を登録:

```bash
crontab -e
```

例:

```cron
0 3 * * * ~/ops/backup_postgres_to_r2.sh >> /var/log/tech_notes_backup.log 2>&1
```

スクリプトが `rclone` に明示的に `--config ~/.config/rclone/rclone.conf` を渡していない限り、`sudo crontab -e` は使用しないでください。

## Cloudflare Workers AI

このアプリケーションは Cloudflare Workers AI を呼び出して、管理画面の記事投稿フォームで要約を生成できます。

### アカウント ID

`CLOUDFLARE_ACCOUNT_ID` には Workers AI 設定を所有する Cloudflare アカウント ID を設定します。

アカウント ID は Cloudflare ダッシュボードのアカウント概要で確認できます。

### API トークン

`CLOUDFLARE_AI_API_TOKEN` には対象アカウントで Workers AI モデルを実行できる API トークンを作成します。

Cloudflare ダッシュボードで:

1. `My Profile` を開く
2. `API Tokens` を開く
3. カスタムトークンを作成する
4. 対象アカウントの Workers AI 使用権限を付与する
5. 生成されたトークンをコピーする

トークンは安全に保管し、リポジトリにコミットしないでください。

### モデル

`CLOUDFLARE_AI_MODEL` には要約生成に使用する Workers AI モデルを設定します。

推奨初期値は `@cf/meta/llama-3.2-1b-instruct` です。

要約品質が十分でない場合は、価格と制限を確認した上で別の Workers AI instruct モデルに切り替えてください。

### タイムアウト

`CLOUDFLARE_AI_TIMEOUT_SECONDS` には Workers AI リクエストの HTTP タイムアウトを設定します。

推奨初期値は `60` です。

## Google Search Console

このアプリケーションは `GOOGLE_SITE_VERIFICATION` 環境変数が設定されている場合に、Google Search Console のサイト所有権確認メタタグを埋め込みます。
タグは `app/views/layouts/application.html.erb` で `GOOGLE_SITE_VERIFICATION` が設定されているときのみレンダリングされるため、変数なしのローカル開発ではタグは出力されません。

### 確認トークン

`GOOGLE_SITE_VERIFICATION` には Google Search Console が発行するメタタグの `content` 値を設定します。タグの形式は以下の通り:

```html
<meta name="google-site-verification" content="..." />
```

タグ全体ではなく `content` の値のみを環境変数に設定してください。

Google Search Console で:

1. `Settings` を開く
2. `Ownership verification` を開く
3. `HTML tag` を確認方法として選択する
4. 表示されたメタタグから `content` 値をコピーする

### Kamal デプロイ

`.kamal/secrets` は上記の [環境変数一覧](#環境変数一覧) からシークレット環境変数を解決します。
すべての `CLOUDFLARE_*`、`GOOGLE_SITE_VERIFICATION`、`RAILS_MASTER_KEY`、`POSTGRES_PASSWORD` は `kamal deploy` を実行する前にシェルで設定しておく必要があります。
`.kamal/secrets` ファイル自体には生の値を含めてはいけません。
