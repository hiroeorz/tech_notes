# 運用セットアップ手順書

## 目次

1. [Cloudflare R2 画像ストレージ](#1-cloudflare-r2-画像ストレージ)
2. [PostgreSQL バックアップ準備](#2-postgresql-バックアップ準備)
3. [Cloudflare Workers AI](#3-cloudflare-workers-ai)
4. [Google Search Console](#4-google-search-console)

---

## 1. Cloudflare R2 画像ストレージ

このアプリケーションは Active Storage を使ってアップロード画像を Cloudflare R2 に保存します。
記事画像は Markdown 内で公開 CDN URL として挿入されます。

### 1.1 バケット名

`CLOUDFLARE_R2_BUCKET` には既存の R2 バケット名を設定します。

Cloudflare ダッシュボードで:

1. `R2 Object Storage` を開く
2. `Buckets` を開く
3. バケット名をコピーする

### 1.2 アクセスキーとシークレット

`CLOUDFLARE_R2_ACCESS_KEY_ID` と `CLOUDFLARE_R2_SECRET_ACCESS_KEY` 用の R2 API トークンを作成します。

Cloudflare ダッシュボードで:

1. `R2 Object Storage` を開く
2. R2 アカウント詳細領域から API トークン管理画面を開く
3. アカウントまたはユーザー API トークンを作成する
4. 対象バケットへのオブジェクト読み書き権限を付与する
5. 生成された `Access Key ID` と `Secret Access Key` をコピーする

シークレットアクセスキーはトークン作成時にのみ表示されます。すぐに保存してください。

### 1.3 R2 エンドポイント

`CLOUDFLARE_R2_ENDPOINT` は Cloudflare アカウント ID から設定します。

```text
https://<ACCOUNT_ID>.r2.cloudflarestorage.com
```

EU 管轄のバケットの場合は EU 固有のエンドポイントを使用します:

```text
https://<ACCOUNT_ID>.eu.r2.cloudflarestorage.com
```

アカウント ID は Cloudflare ダッシュボードのアカウント概要で確認できます。

### 1.4 公開 CDN URL

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

---

## 2. PostgreSQL バックアップ準備

本番環境の PostgreSQL バックアップは VM ホスト上の cron で実行されます。
バックアップのアーキテクチャ・ポリシーは `docs/backup-requirements.md` を参照してください。

### 2.1 Cloudflare R2 セットアップ

バックアップ用のバケットを作成し、API キーを発行します。

Cloudflare ダッシュボードで:

1. `R2 Object Storage` を開く
2. バックアップ用バケット（例: `your-project-backup`）を作成または開く
3. バケット用の R2 API トークンまたはアクセスキーを作成する
4. 対象バケットへのオブジェクト読み書き権限を付与する
5. 生成された `Access Key ID` と `Secret Access Key` をコピーする

画像バケットのキーを流用せず、バックアップ専用のキーを使用してください。画像バケットのみにアクセスできるキーではバックアップバケットへの書き込み時に `403 Forbidden` が発生します。

### 2.2 VM rclone セットアップ

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

### 2.3 R2 書き込みテスト

`copyto` でアップロードをテストします。このバックアップフローでは `rclone rcat` を使用しないでください（ストリーミングアップロードは R2 で `501 NotImplemented` になる可能性があります）。

```bash
tmp=$(mktemp)
echo "test $(date)" > "$tmp"

rclone copyto "$tmp" r2:your-project-backup/postgresql/rclone_test.txt --s3-no-check-bucket
rclone cat r2:your-project-backup/postgresql/rclone_test.txt --s3-no-check-bucket
rclone deletefile r2:your-project-backup/postgresql/rclone_test.txt --s3-no-check-bucket

rm "$tmp"
```

アップロードが `403 Forbidden` で失敗する場合は、バックアップバケットへのオブジェクト読み書き権限を持つ R2 アクセスキーを再作成してください。

### 2.4 VM cron 準備

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

---

## 3. Cloudflare Workers AI

このアプリケーションは Cloudflare Workers AI を呼び出して、管理画面の記事投稿フォームで要約を生成できます。

### 3.1 アカウント ID

`CLOUDFLARE_ACCOUNT_ID` には Workers AI 設定を所有する Cloudflare アカウント ID を設定します。

アカウント ID は Cloudflare ダッシュボードのアカウント概要で確認できます。

### 3.2 API トークン

`CLOUDFLARE_AI_API_TOKEN` には対象アカウントで Workers AI モデルを実行できる API トークンを作成します。

Cloudflare ダッシュボードで:

1. `My Profile` を開く
2. `API Tokens` を開く
3. カスタムトークンを作成する
4. 対象アカウントの Workers AI 使用権限を付与する
5. 生成されたトークンをコピーする

トークンは安全に保管し、リポジトリにコミットしないでください。

### 3.3 モデル

`CLOUDFLARE_AI_MODEL` には要約生成に使用する Workers AI モデルを設定します。

推奨初期値は `@cf/meta/llama-3.2-1b-instruct` です。

要約品質が十分でない場合は、価格と制限を確認した上で別の Workers AI instruct モデルに切り替えてください。

### 3.4 タイムアウト

`CLOUDFLARE_AI_TIMEOUT_SECONDS` には Workers AI リクエストの HTTP タイムアウトを設定します。

推奨初期値は `60` です。

---

## 4. Google Search Console

このアプリケーションは `GOOGLE_SITE_VERIFICATION` 環境変数が設定されている場合に、Google Search Console のサイト所有権確認メタタグを埋め込みます。
タグは `app/views/layouts/application.html.erb` で `GOOGLE_SITE_VERIFICATION` が設定されているときのみレンダリングされるため、変数なしのローカル開発ではタグは出力されません。

### 4.1 確認トークン

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
