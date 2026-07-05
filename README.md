# Hiroe Tech Notes

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
export APP_HOST="hiroe-tech-notes.example.com"      # 本番ホスト名（production必須）
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
# Kamal デプロイ用 (デプロイ実行環境でのみ必要)
# ============================================
export IMAGE="hiroeorz/tech_notes"                      # Dockerイメージ名
export SERVER_IP="192.168.0.1"                          # デプロイ先サーバーIP
export PROXY_HOST="hiroe-tech-notes.example.com"        # SSLプロキシホスト名
export REGISTRY_USERNAME="hiroeorz"                     # Docker Hubユーザー名
export SSH_USER="deploy"                                # SSH接続ユーザー
export KAMAL_REGISTRY_PASSWORD="your-docker-hub-token"  # Docker Hubアクセストークン
export RAILS_MASTER_KEY="$(cat config/master.key)"      # credentials復号キー
```

> **補足**: `POSTGRES_PASSWORD` / Cloudflare 関連の一部変数は `config/credentials.yml.enc` からのフォールバックを持ちます。上記でコメントアウトした変数は全てコード内にデフォルト値が定義されており、未設定でもアプリは動作します。

---

## Cloudflare R2 image storage

This application stores uploaded images with Active Storage on Cloudflare R2.
Article images are inserted into Markdown as public CDN URLs.

### Bucket name

Use the existing R2 bucket name for `CLOUDFLARE_R2_BUCKET`.

In Cloudflare Dashboard:

1. Open `R2 Object Storage`.
2. Open `Buckets`.
3. Copy the bucket name.

### Access key and secret

Create an R2 API token for `CLOUDFLARE_R2_ACCESS_KEY_ID` and
`CLOUDFLARE_R2_SECRET_ACCESS_KEY`.

In Cloudflare Dashboard:

1. Open `R2 Object Storage`.
2. Open the API token management screen from the R2 account details area.
3. Create an account or user API token.
4. Grant object read/write access to the target bucket.
5. Copy the generated `Access Key ID` and `Secret Access Key`.

The secret access key is shown only when the token is created. Store it
immediately.

### R2 endpoint

Set `CLOUDFLARE_R2_ENDPOINT` from the Cloudflare account ID.

For an EU jurisdiction bucket, use the EU-specific endpoint:

```text
https://<ACCOUNT_ID>.eu.r2.cloudflarestorage.com
```

The account ID is available in the Cloudflare Dashboard account overview.

### Public CDN URL

Set `ACTIVE_STORAGE_PUBLIC_BASE_URL` to the public CDN URL used for R2 object
delivery. A custom domain on the R2 bucket is recommended.

In Cloudflare Dashboard:

1. Open `R2 Object Storage`.
2. Open the target bucket.
3. Open `Settings`.
4. Add a domain under `Custom Domains`.
5. Wait until the domain status becomes active.

The CDN URL must serve objects by their Active Storage blob key. For example,
if the blob key is `abc123`, this URL must return the image:

```text
https://cdn.example.com/abc123
```

## PostgreSQL backup preparation

Production PostgreSQL backups are run from the VM host with cron. The backup
script is documented in `docs/backup-requirements.md` and is expected to upload
dump files to Cloudflare R2 with `rclone copyto`.

The backup bucket is:

```text
hiroe-tech-notes-backup
```

### Cloudflare R2 setup

In Cloudflare Dashboard:

1. Open `R2 Object Storage`.
2. Create or open the `hiroe-tech-notes-backup` bucket.
3. Create an R2 API token or access key for the backup bucket.
4. Grant object read/write access to `hiroe-tech-notes-backup`.
5. Copy the generated `Access Key ID` and `Secret Access Key`.

Use a backup-specific key instead of reusing the image bucket key. A key that
only has access to the image bucket will fail with `403 Forbidden` when writing
to `hiroe-tech-notes-backup`.

### VM rclone setup

Install `rclone` on the VM host:

```bash
sudo apt update
sudo apt install -y rclone
rclone version
```

Configure the `r2` remote as the same user that will run cron. The production
VM uses the `hiroe` user.

```bash
rclone config
```

Use these values:

```text
name = r2
type = s3
provider = Cloudflare
region = auto
endpoint = https://<ACCOUNT_ID>.r2.cloudflarestorage.com
acl = private
no_check_bucket = true
```

Set `access_key_id` and `secret_access_key` to the backup bucket key created in
Cloudflare.

Confirm the config file location:

```bash
rclone config file
```

For the `hiroe` user, it is usually:

```text
/home/hiroe/.config/rclone/rclone.conf
```

### R2 write test

Test upload with `copyto`. Do not use `rclone rcat` for this backup flow,
because streaming uploads can fail against R2 with `501 NotImplemented`.

```bash
tmp=$(mktemp)
echo "test $(date)" > "$tmp"

rclone copyto "$tmp" r2:hiroe-tech-notes-backup/postgresql/rclone_test.txt --s3-no-check-bucket
rclone cat r2:hiroe-tech-notes-backup/postgresql/rclone_test.txt --s3-no-check-bucket
rclone deletefile r2:hiroe-tech-notes-backup/postgresql/rclone_test.txt --s3-no-check-bucket

rm "$tmp"
```

If the upload fails with `403 Forbidden`, recreate the R2 access key with
object read/write access to `hiroe-tech-notes-backup`.

### VM cron preparation

Create the script destination directory:

```bash
mkdir -p /home/hiroe/ops
chmod 750 /home/hiroe/ops
```

Create the backup log file:

```bash
sudo touch /var/log/tech_notes_backup.log
sudo chown hiroe:hiroe /var/log/tech_notes_backup.log
chmod 640 /var/log/tech_notes_backup.log
```

Confirm the Kamal PostgreSQL accessory container is visible:

```bash
docker ps --filter label=service=tech_notes-db --format '{{.Names}}'
```

After `script/ops/backup_postgres_to_r2.sh` is deployed to
`/home/hiroe/ops/backup_postgres_to_r2.sh`, register cron as the `hiroe` user:

```bash
crontab -e
```

Example:

```cron
0 3 * * * /home/hiroe/ops/backup_postgres_to_r2.sh >> /var/log/tech_notes_backup.log 2>&1
```

Do not use `sudo crontab -e` unless the script explicitly passes
`--config /home/hiroe/.config/rclone/rclone.conf` to `rclone`.

## Cloudflare Workers AI

This application can call Cloudflare Workers AI to generate draft article
summaries in the admin post form.

### Account ID

Set `CLOUDFLARE_ACCOUNT_ID` to the Cloudflare account ID that owns the Workers
AI configuration.

The account ID is available in the Cloudflare Dashboard account overview.

### API token

Create an API token for `CLOUDFLARE_AI_API_TOKEN` that can run Workers AI
models for the target account.

In Cloudflare Dashboard:

1. Open `My Profile`.
2. Open `API Tokens`.
3. Create a custom token.
4. Grant the token permission to use Workers AI for the target account.
5. Copy the generated token.

Store the token securely. Do not commit it to the repository.

### Model

Set `CLOUDFLARE_AI_MODEL` to the Workers AI model used for summary generation.

The initial recommended value is `@cf/meta/llama-3.2-1b-instruct`.

If summary quality is not sufficient, switch this value to another Workers AI
instruct model after checking pricing and limits.

### Timeout

Set `CLOUDFLARE_AI_TIMEOUT_SECONDS` to the HTTP timeout for Workers AI requests.

The recommended initial value is `60`.

## Google Search Console

This application embeds the Google Search Console site verification meta tag
when the verification token is provided via an environment variable. The tag is
rendered in `app/views/layouts/application.html.erb` only when
`GOOGLE_SITE_VERIFICATION` is set, so local development without the variable
produces no tag.

### Verification token

Set `GOOGLE_SITE_VERIFICATION` to the `content` value of the meta tag issued by
Google Search Console. The tag has the form:

```html
<meta name="google-site-verification" content="..." />
```

Copy only the `content` value (not the entire tag) into the environment
variable.

In Google Search Console:

1. Open `Settings`.
2. Open `Ownership verification`.
3. Select `HTML tag` as the verification method.
4. Copy the `content` value from the displayed meta tag.

### Kamal deployment

`.kamal/secrets` resolves the secret env vars from the [環境変数一覧](#環境変数一覧) above.
All `CLOUDFLARE_*`, `GOOGLE_SITE_VERIFICATION`, `RAILS_MASTER_KEY`, and
`POSTGRES_PASSWORD` must be set in the shell before running `kamal deploy`.
The `.kamal/secrets` file itself must not contain raw values.
