# Hiroe Tech Notes デプロイ仕様書

## 1. 概要

本ドキュメントは、「Hiroe Tech Notes」アプリケーションを単一VM（VPS等）上に低コストかつ堅牢にデプロイ・運用するためのインフラアーキテクチャおよびデプロイ仕様を定義する。

マネージドサービスを使用せず、**Kamal** を用いて Web アプリケーション（Rails）と データベース（PostgreSQL）の両方を Docker コンテナとして単一サーバー上に構成し、データを永続化する。SSL 終端は Kamal 内蔵のリバースプロキシ（Traefik）と Let's Encrypt 自動発行で行う。

---

## 2. システム構成・アーキテクチャ

### 2.1 全体構成図

```text
+------------------------------------------------------------------------+
|  Single VM / VPS (e.g. 1〜2GB RAM, SWAP Enabled)                       |
|                                                                        |
|  +--------------------------------------------------------------+     |
|  |  Kamal Deployment & Container Management                     |     |
|  +--------------------------------------------------------------+     |
|                                                                        |
|                      +-----------------------------+                  |
|  Internet ---------> | Kamal Proxy (Traefik)       |                  |
|  (HTTPS, Let's       |  - Port 80  → redirect 443  |                  |
|   Encrypt autorenew) |  - Port 443 → forward to web|                  |
|                      +-----------------------------+                  |
|                              |                                         |
|                              v                                         |
|  +------------------------+   +----------------------------+         |
|  | Web Container          |   | Accessory Container (db)   |         |
|  | (Rails 8 / Puma)       | ->| (PostgreSQL 16 Alpine)     |         |
|  |  DB_HOST=tech_notes-db |   | port: 127.0.0.1:5432       |         |
|  +------------------------+   +----------------------------+         |
|                                              |                        |
|                                              v                        |
|                                +----------------------------+         |
|                                | Persistent Volume (host)   |         |
|                                | postgres-data              |         |
|                                | /var/lib/postgresql/data   |         |
|                                +----------------------------+         |
+------------------------------------------------------------------------+
```

### 2.2 コンテナ・プロキシ設計

| コンポーネント | 役割 | 使用イメージ | ネットワーク / ポート |
| :--- | :--- | :--- | :--- |
| **Kamal Proxy** | SSL 終端 / リバースプロキシ / Let's Encrypt 証明書自動発行 | Kamal 箄製 (Traefik) | 80/443 (HTTP/HTTPS) |
| **Web** | Rails アプリケーション (Puma / Thruster) | カスタムビルド (`Dockerfile`) | 内部のみ（プロキシ経由） |
| **Accessory (db)** | データベース | `postgres:16-alpine` | `127.0.0.1:5432:5432`（ローカルバインド） |

### 2.3 データベース論理構成

PostgreSQL は1クラスタ上に以下の4つの論理データベースを保持する。`config/postgres/init.sql` が初回起動時に作成する。

| 論理 DB | 用途 | env で指定する変数 |
| :--- | :--- | :--- |
| `tech_notes_production` | 記事・カテゴリ・タグ・管理ユーザ・設定など主要データ | `POSTGRES_DB` |
| `tech_notes_production_cache` | Solid Cache | `POSTGRES_DB_CACHE` |
| `tech_notes_production_queue` | Solid Queue (Active Job) | `POSTGRES_DB_QUEUE` |
| `tech_notes_production_cable` | Solid Cable (Action Cable) | `POSTGRES_DB_CABLE` |

---

## 3. 永続化ストレージ設計

データベースの実データはコンテナの破棄・再作成（デプロイ時）によって消失しないよう、**VM（ホスト）上のディレクトリへマウント**して永続化する。

* **DB 永続化**: `directories: - postgres-data:/var/lib/postgresql/data`
  * Kamal は `directories:` で指定したパスをホスト側ディレクトリとしてマウントする（Docker named volume ではない）。
  * コンテナが更新・再起動されても、ホスト上の `postgres-data` ディレクトリに保持されるためデータは維持される。
* **Active Storage ファイル**: Cloudflare R2
  * Active Storage のアップロードファイル（記事画像・OGP 画像・プロフィール画像など）は R2 に保存する。
  * Rails からは S3 互換 API で接続し、公開記事中の画像は public CDN 経由で配信する。

---

## 4. ネットワークとセキュリティ

1. **DB アクセス制限**
   * PostgreSQL のポート（5432）は `127.0.0.1:5432:5432` にバインドし、外部インターネットからの直接接続をブロックする。
   * Web コンテナから DB コンテナへは、Kamal が構成する内部 Docker ネットワーク経由で、**アクセサリ名 `tech_notes-db`** をホスト名としてアクセスする（`DB_HOST=tech_notes-db`）。
   * ※外部公開 IP への接続や `127.0.0.1` では Web コンテナから到達できない点に注意。
2. **SSL / HTTPS**
   * Kamal proxy が Let's Encrypt で証明書を自動取得・更新し、80/443 をリッスンする。
   * 80 は 443 へリダイレクト。443 は復号後に Web コンテナへ HTTP 転送する。
   * Rails 側は `config.assume_ssl = true` / `config.force_ssl = true` を有効化済み。
3. **環境変数・シークレット管理**
   * DB パスワード等の機密情報は Kamal の `.kamal/secrets` と環境変数経由で安全にコンテナへ注入する（平文で `config/deploy.yml` には書かない）。
   * 必須シークレット: `RAILS_MASTER_KEY`, `POSTGRES_PASSWORD`。
   * R2 利用時の必須シークレット: `CLOUDFLARE_R2_ACCESS_KEY_ID`, `CLOUDFLARE_R2_SECRET_ACCESS_KEY`, `CLOUDFLARE_R2_BUCKET`, `CLOUDFLARE_R2_ENDPOINT`, `ACTIVE_STORAGE_PUBLIC_BASE_URL`。
4. **DNS Rebinding 保護**
   * `config.hosts` に本番ドメイン `hiroe-tech-notes.aomaro.com` のみを許可し、`/up` はヘルスチェック用に除外している。

---

## 5. デプロイ設定 (`config/deploy.yml`)

シングルVM環境における基本構成を以下に示す。実運用時は `192.168.0.1` の IP と Docker Hub 認証情報を実値に置き換える。

```yaml
service: tech_notes

image: hiroeorz/tech_notes

servers:
  web:
    - 192.168.0.1

# SSL via Kamal proxy + Let's Encrypt 自動発行。
# Cloudflare を前段に置く場合は Cloudflare の SSL/TLS 設定を "Full" にすること。
proxy:
  ssl: true
  host: hiroe-tech-notes.aomaro.com

registry:
  server: docker.io
  username: hiroe
  # password:
  #   - KAMAL_REGISTRY_PASSWORD

env:
  secret:
    - RAILS_MASTER_KEY
    - POSTGRES_PASSWORD
    - CLOUDFLARE_R2_ACCESS_KEY_ID
    - CLOUDFLARE_R2_SECRET_ACCESS_KEY
    - CLOUDFLARE_R2_BUCKET
    - CLOUDFLARE_R2_ENDPOINT
    - ACTIVE_STORAGE_PUBLIC_BASE_URL
  clear:
    RAILS_ENV: production
    SOLID_QUEUE_IN_PUMA: true
    DB_HOST: tech_notes-db
    POSTGRES_DB: tech_notes_production
    POSTGRES_USER: hiroe
    POSTGRES_DB_CACHE: tech_notes_production_cache
    POSTGRES_DB_QUEUE: tech_notes_production_queue
    POSTGRES_DB_CABLE: tech_notes_production_cable

asset_path: /rails/public/assets

healthcheck:
  path: /up
  interval: 10
  timeout: 5

builder:
  arch: amd64

accessories:
  db:
    image: postgres:16-alpine
    host: 192.168.0.1
    port: "127.0.0.1:5432:5432"
    env:
      clear:
        POSTGRES_DB: tech_notes_production
        POSTGRES_USER: hiroe
      secret:
        - POSTGRES_PASSWORD
    files:
      - config/postgres/init.sql:/docker-entrypoint-initdb.d/init.sql
    directories:
      - postgres-data:/var/lib/postgresql/data

aliases:
  console: app exec --interactive --reuse "bin/rails console"
  shell: app exec --interactive --reuse "bash"
  logs: app logs -f
  dbc: app exec --interactive --reuse "bin/rails dbconsole --include-password"
```

### 5.1 PostgreSQL 初期化 SQL (`config/postgres/init.sql`)

Accessory コンテナ初回起動時に Solid Cache / Queue / Cable 用の論理データベースを作成する。

```sql
-- Initialise the Solid Cache / Solid Queue / Solid Cable logical databases.
CREATE DATABASE tech_notes_production_cache;
CREATE DATABASE tech_notes_production_queue;
CREATE DATABASE tech_notes_production_cable;
```

---

## 6. 運用・保守設計

### 6.1 バックアップ方針

マネージドDBを使用しないため、日次の自動バックアップ運用を行う。

* **手法**: VM上の `cron` により、毎日 **午前3:00 JST** に `pg_dump` を実行し、4つの論理DBすべてを 1 つの custom 形式ダンプファイルにまとめる。
* **コマンド例**:
  ```bash
  0 3 * * * /usr/local/bin/pg_dump_all.sh
  ```
  ```bash
  #!/usr/bin/env bash
  set -eu
  DUMP_DIR=/var/backups/tech_notes
  STAMP=$(date +%Y%m%d_%H%M%S)
  DUMP_FILE=$DUMP_DIR/tech_notes_$STAMP.dump
  mkdir -p "$DUMP_DIR"

  docker exec tech_notes-db pg_dump \
    -U hiroe \
    -Fc \
    -d tech_notes_production \
    > "$DUMP_FILE"

  # Solid系DBも併せてダンプ
  for db in _cache _queue _cable; do
    docker exec tech_notes-db pg_dump -U hiroe -Fc -d "tech_notes_production$db" \
      > "$DUMP_DIR/tech_notes${db}_$STAMP.dump"
  done

  # Cloudflare R2 へ同期
  rclone copy "$DUMP_DIR" r2:tech_notes-backups/
  # 30世代（約1ヶ月分）より古いダンプを削除
  find "$DUMP_DIR" -name "tech_notes*.dump" -mtime +30 -delete
  ```
* **保存先**: **Cloudflare R2**（S3互換オブジェクトストレージ）。
* **保持期間**: **30世代（約1ヶ月分）** を保持し、超過分は本スクリプトで削除する。必要に応じて R2 側のライフサイクルルールで二重に管理してもよい。
* **選定理由・メリット**:
  * **データ転送手数料（Egress料金）が完全無料**。
  * 毎月 10GB までの無料ストレージ枠があり、個人ブログのDBバックアップ用途では実質無料運用が可能。
  * S3互換APIを備えているため、`rclone` や `aws s3` / `mc` などの標準クライアントで簡単にアップロード可能。

### 6.2 リソース管理・メモリ見積もり

「アクセス頻度が低めの個人ブログ」として運用する場合の推奨VMスペックおよびメモリ内訳は以下の通り。

| 構成要素 | アイドル/常駐メモリ使用量（目安） |
| :--- | :--- |
| **OS (Linux) + Docker Daemon + Kamal Proxy** | 約 250MB 〜 350MB |
| **Rails 8 (Puma / Thruster)** | 約 150MB 〜 250MB |
| **PostgreSQL 16 (Alpine)** | 約 50MB 〜 100MB |
| **常駐合計** | **約 450MB 〜 700MB** |

#### メモリ運用とSWAP領域の設定

* **推奨メモリサイズ**: **1GB RAM**（月額500円前後の最安VPSプランで十分対応可能）
* **必須設定**: **1GB 〜 2GB の SWAP 領域（仮想メモリ）**
* **スパイク要因（SWAPが必要な理由）**:
  通常時のメモリ使用量は 600MB 前後に収まるが、以下の処理時に一時的にメモリ使用量が 800MB〜1GB 近くまで増加する可能性があるため、OOM Killer によるコンテナ強制終了を防ぐ目的で SWAP 設定を必須とする。
  1. アプリ更新時（`kamal deploy` による新コンテナ起動・移行処理）
  2. 日次バックアップ実行時（`pg_dump` 処理）
  3. サーバー上でのメンテナンスコマンド実行時（`rails console` 等の起動）
* ※さらに余裕を持った安定運用を希望する場合は **2GB RAM** プランを選択する。

### 6.3 ヘルスチェック

`config/deploy.yml` の `healthcheck` ブロックで `/up` を監視する。Kamal は新コンテナ起動後、`/up` が `200` を返すまで旧コンテナを残し、準備できたタイミングでトラフィックを切り替える（ゼロダウンタイム更新）。

```yaml
healthcheck:
  path: /up
  interval: 10
  timeout: 5
```

### 6.4 ログとディスク管理

* **Rails / Kamal ログ**: ログはコンテナ内の標準出力に出力されるため、`kamal app logs -f` で追従可能。長期保存が必要な場合は外部ログサービスへの転送を推奨。
* **PostgreSQL ログ**: `kamal accessory logs db` で確認可能。
* **ディスク監視**: VPS 上で `df -h` を定期実行するか、簡易アラートを設定し、`pg_dump` 残骸やログ肥大化によるディスク枯渇を防止する。

---

## 7. Kamal 操作コマンドリファレンス

| 操作 | コマンド | 概要 |
| :--- | :--- | :--- |
| **初回セットアップ** | `kamal setup` | サーバー初期化、DBアクセサリ起動、アプリデプロイを一括実行 |
| **通常デプロイ** | `kamal deploy` | 最新イメージのビルドおよびアプリケーションのゼロダウンタイム更新 |
| **DBコンテナ起動** | `kamal accessory boot db` | データベースコンテナのみを起動 |
| **DBコンテナ再起動** | `kamal accessory reboot db` | データベースコンテナのみを再起動 |
| **コンテナログ確認** | `kamal app logs` | Rails アプリケーションのログを表示 |
| **DBコンテナログ** | `kamal accessory logs db` | PostgreSQL のログを表示 |
| **Rails コンソール** | `kamal console`（alias） | コンテナ内で `bin/rails console` を起動 |
| **DB クライアント** | `kamal dbc`（alias） | コンテナ内で `bin/rails dbconsole` を起動 |
| **マイグレーション** | `kamal app exec --reuse "bin/rails db:migrate"` | コンテナ内で未適用のマイグレーションを実行 |

---

## 8. 初回デプロイ手順（想定）

1. VPS 上に SWAP を 1〜2GB 設定。
2. `config/master.key` と `.kamal/secrets` に `POSTGRES_PASSWORD`, `RAILS_MASTER_KEY` を安全な方法で設定。
3. `config/deploy.yml` の `servers.web` と `registry` 情報を実値に書き換え。
4. Cloudflare R2 のバケットを作成し、`rclone` 等の認証情報を VM に設定。
5. `kamal setup` を実行（プロキシの起動・DB accessory 起動・`db:prepare`・初回デプロイを一括実施）。
6. DNS で `hiroe-tech-notes.aomaro.com` を VPS のパブリックIPに向ける（Let's Encrypt の発行に必要）。
7. `https://hiroe-tech-notes.aomaro.com/` にアクセスして表示確認。
8. バックアップ用の cron スクリプトを `crontab` に登録。
