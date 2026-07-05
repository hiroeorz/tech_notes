---
name: deploy
description: Kamal を使った本番デプロイの事前準備・実行手順・トラブルシューティング・ロールバック手順を定義する。docker build からコンテナ起動確認までをカバーする。
---

`kamal deploy` による本番デプロイを実行する前に、このスキルの手順に従うこと。

## 事前準備

### 1. 環境変数の確認

デプロイを実行するマシンで以下の環境変数が設定されていることを確認する。値は `~/.bashrc` や `.env` ファイル等で管理し、`.kamal/secrets` と `config/deploy.yml` の ERB が解決できるようにする。

**必須変数:**

| 変数名 | 用途 |
|--------|------|
| `IMAGE` | Dockerイメージ名（例: `hiroeorz/tech_notes`） |
| `SERVER_IP` | デプロイ先サーバーのパブリックIP |
| `PROXY_HOST` | SSLプロキシホスト名（Let's Encrypt対象ドメイン） |
| `REGISTRY_USERNAME` | Docker Hubユーザー名 |
| `SSH_USER` | サーバーへのSSH接続ユーザー |
| `POSTGRES_USER` | PostgreSQLユーザー名 |
| `APP_HOST` | 本番ホスト名（`config/environments/production.rb` で使用） |
| `POSTGRES_PASSWORD` | PostgreSQLパスワード |
| `KAMAL_REGISTRY_PASSWORD` | Docker Hubアクセストークン |
| `RAILS_MASTER_KEY` | `cat config/master.key` の値 |
| `CLOUDFLARE_R2_ACCESS_KEY_ID` | R2アクセスキー |
| `CLOUDFLARE_R2_SECRET_ACCESS_KEY` | R2シークレットキー |
| `CLOUDFLARE_R2_BUCKET` | R2バケット名 |
| `CLOUDFLARE_R2_ENDPOINT` | R2エンドポイント |
| `ACTIVE_STORAGE_PUBLIC_BASE_URL` | 公開CDNのベースURL |

**AI要約・Google Search Console を使用する場合は以下も必要:**

| 変数名 | 用途 |
|--------|------|
| `CLOUDFLARE_ACCOUNT_ID` | Workers AIアカウントID |
| `CLOUDFLARE_AI_API_TOKEN` | Workers AI APIトークン |
| `CLOUDFLARE_AI_MODEL` | Workers AIモデル名 |
| `CLOUDFLARE_AI_TIMEOUT_SECONDS` | AIリクエストタイムアウト（秒） |
| `GOOGLE_SITE_VERIFICATION` | Search Console所有権確認トークン |

### 2. README.md の環境変数一覧を更新する

新しい環境変数を追加した場合は、`README.md` の「環境変数一覧」に対応するサンプルと説明を追記すること。デプロイ時に不足に気づく前に、セットアップ者が事前に把握できるようにするため。

### 3. `.kamal/secrets` の整合性確認

`.kamal/secrets` は環境変数を `$VARNAME` で参照している。全ての変数が実際の環境で設定済みであることを確認する。

```bash
# 不足があると kamal 実行時にエラーになる
env | grep -E '^(POSTGRES_PASSWORD|KAMAL_REGISTRY_PASSWORD|RAILS_MASTER_KEY|CLOUDFLARE_|GOOGLE_SITE_VERIFICATION|IMAGE|SERVER_IP|PROXY_HOST|REGISTRY_USERNAME|SSH_USER|POSTGRES_USER|APP_HOST)'
```

### 4. SSH接続の確認

```bash
ssh -t <SSH_USER>@<SERVER_IP> "docker --version && kamal version"
```

### 5. デプロイ内容の確認

```bash
# 現在のブランチとコミットを確認
git log --oneline -5

# 未プッシュのコミットがないか確認
git log --oneline origin/main..HEAD

# 未コミットの変更がないか確認
git status
```

**未プッシュのコミットがあってもデプロイは可能だが、ロールバック時に Docker Hub にイメージが存在しないと `kamal rollback` が失敗する。** そのため本番デプロイ前には最新のコミットをプッシュしておくことを推奨する。`kamal deploy` はローカルのファイルから Docker イメージをビルドする（GitHub から取得するわけではない）。

## デプロイ手順

### 初回デプロイ

```bash
kamal setup
```

`kamal setup` は以下を一括実行する:
1. サーバーに Docker がインストールされていることを確認（なければ自動インストール）
2. Kamal Proxy（Traefik）の起動
3. DB accessory（PostgreSQL）の起動
4. `.kamal/secrets` をサーバーにアップロード
5. アプリイメージのビルドとプッシュ
6. コンテナ起動とヘルスチェック
7. Let's Encrypt 証明書の自動取得

### 通常デプロイ

```bash
# 事前にイメージをプッシュ（kamal deploy 内部で自動で行われる）
kamal deploy
```

`kamal deploy` の内部動作:
1. ローカルで Docker イメージをビルド
2. Docker Hub にイメージをプッシュ
3. サーバー上で新コンテナを起動
4. `/up` エンドポイントのヘルスチェックが成功するまで待機
5. Kamal Proxy のルーティングを新コンテナに切り替え
6. 旧コンテナを停止・削除

### デプロイ後の確認

```bash
# アプリケーションログ
kamal app logs -f

# コンテナステータス
kamal app details

# DB コンテナの状態
kamal accessory details db

# 実際の HTTP 応答確認
curl -I https://<APP_HOST>/
curl -s -o /dev/null -w "%{http_code}" https://<APP_HOST>/up
```

## トラブルシューティング

### ビルドに失敗する

- `config/deploy.yml` の `builder.arch` がデプロイ環境のアーキテクチャと一致しているか確認する。
- Docker Hub の認証情報（`KAMAL_REGISTRY_PASSWORD`）が有効か確認する。
- Docker デーモンが起動しているか確認する。

### Let's Encrypt の証明書取得に失敗する

- DNS レコードがサーバーの IP を正しく指しているか確認する。
- Kamal Proxy が 80/443 ポートで待受可能か確認する（権限・ポート競合）。
- `config/deploy.yml` の `proxy.host` が正しいドメイン名か確認する。

### DB コンテナが起動しない

```bash
kamal accessory logs db
```

- ホストの `postgres-data` ディレクトリのパーミッションを確認する。
- ディスク容量が十分あるか確認する（`df -h`）。

### アプリが 502 を返す

```bash
kamal app logs -f
```

- ヘルスチェックパス `/up` が正しいレスポンスを返しているか確認する。
- DB 接続設定（`DB_HOST`, `POSTGRES_USER`, `POSTGRES_PASSWORD`）が正しいか確認する。
- `bin/docker-entrypoint` の `db:prepare` が成功しているか確認する。

## ロールバック

```bash
# 特定バージョン（Git SHA）へロールバック
kamal rollback <git-sha>
```

注意点:
- ロールバックは以前の Docker イメージが Docker Hub に残っている場合のみ可能。
- `kamal rollback` はイメージを再ビルドせず、既存のイメージタグを指定する。
- DB マイグレーションのロールバックは自動では行われない。必要に応じて手動で実行する:

```bash
kamal app exec --reuse "bin/rails db:migrate:down VERSION=<前バージョン>"
```

## メンテナンス操作

### ワンショットコマンド実行

```bash
# Rails コンソール
kamal console

# DB コンソール
kamal dbc

# 任意のコマンド
kamal app exec --reuse "bin/rails db:migrate"

# インタラクティブシェル
kamal shell
```

### DB アクセサリの再起動

```bash
kamal accessory reboot db
```

### ログの確認

```bash
kamal app logs                          # Rails/Puma ログ
kamal app logs --since 5m               # 最近5分のログ
kamal accessory logs db                 # PostgreSQL ログ
kamal accessory logs db -n 100          # 最新100行
```

## バックアップ

バックアップはサーバー上の cron で自動実行される（`script/ops/backup_postgres_to_r2.sh`）。

### 手動バックアップ

```bash
kamal app exec --reuse "script/ops/backup_postgres_to_r2.sh"
```

またはサーバー上で直接:

```bash
ssh <SSH_USER>@<SERVER_IP> "sudo docker exec tech_notes-db pg_dump -U <POSTGRES_USER> -Fc -d tech_notes_production" > ./manual_backup.dump
```

## デプロイ失敗時の対応フロー

1. `kamal deploy` のエラーメッセージを確認
2. 原因を特定:
   - ビルドエラー → コードの修正、コミット、プッシュ、再デプロイ
   - ヘルスチェック失敗 → `kamal app logs` でアプリログを確認。DB接続等を確認
   - 証明書エラー → DNS設定、ポート競合を確認
3. 旧バージョンが動いている場合は影響なし（Kamalはヘルスチェック成功まで旧コンテナを維持する）
4. どうしても復旧できない場合は `kamal rollback <直前の正常SHA>` を実行

## デプロイ仕様参照

デプロイアーキテクチャの詳細は `docs/deployment.md` を参照すること。
