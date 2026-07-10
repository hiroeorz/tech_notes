# Hiroe Tech Notes バックアップ要件書

## 1. 概要

本ドキュメントは、Hiroe Tech Notes の本番 PostgreSQL バックアップ運用要件を定義する。

対象環境は、Kamal により単一 VM 上へ Rails アプリケーションと PostgreSQL accessory をデプロイする本番構成とする。VM は 1GB RAM 程度の低リソース構成を想定し、バックアップ運用は追加の常駐コンテナを増やさない方針とする。

Cloudflare R2 上の Active Storage 実ファイルのバックアップは本ドキュメントの主対象外とする。ただし、PostgreSQL には Active Storage の blob / attachment メタデータが含まれるため、R2 実ファイルと DB の整合性には注意する。

## 2. 基本方針

- PostgreSQL バックアップは、本番 VM ホスト上の cron から定期実行する。
- バックアップスクリプトはリポジトリ内で管理し、Kamal deploy 時に VM ホストへ配布する。
- Kamal hook はスクリプト配布に留め、cron 登録そのものは VM 上で手動管理する。
- Rails web コンテナ内に `pg_dump` / `rclone` を追加しない。
- バックアップ専用の常駐 Kamal role / cron コンテナは作成しない。
- PostgreSQL のポートは外部公開せず、VM 内から `docker exec` で dump を取得する。
- dump のアップロード先は`R2_BUCKET`環境変数で指定する Cloudflare R2 バケットとし、一時ファイルへ dump した後に `rclone copyto` で保存する。

## 3. 対象データベース

PostgreSQL accessory 上の以下の論理 DB をバックアップ対象とする。

| 論理 DB | 用途 | 優先度 |
| :--- | :--- | :--- |
| `tech_notes_production` | 記事、タグ、管理ユーザ、サイト設定、Active Storage メタデータなど主要データ | 必須 |
| `tech_notes_production_cache` | Solid Cache | 任意 |
| `tech_notes_production_queue` | Solid Queue | 推奨 |
| `tech_notes_production_cable` | Solid Cable | 推奨 |

低負荷で段階導入する場合は、まず `tech_notes_production` のみを対象にしてよい。復旧作業を単純にする場合は 4 DB すべてを順番にバックアップする。

## 4. 実行方式

### 4.1 VM ホスト cron

本番 VM ホスト上の cron からバックアップスクリプトを実行する。

想定 cron:

```cron
0 3 * * * <BACKUP_DEPLOY_DIR>/backup_postgres_to_r2.sh >> /var/log/tech_notes_backup.log 2>&1
```

実行時刻は、通常アクセスが少ない時間帯を選ぶ。1GB RAM 構成では、複数 DB の dump を並列実行せず、必ず 1 DB ずつ順番に実行する。

### 4.2 DB コンテナの特定

Kamal accessory の DB コンテナは、Docker label `service=tech_notes-db` で特定する。

```bash
docker ps --filter label=service=tech_notes-db --format '{{.Names}}'
```

バックアップスクリプトは、この結果から実コンテナ名を取得する。`tech_notes-db` は Rails コンテナから見た DB ホスト名として使われるが、`docker exec` のコンテナ名として常に使えるとは限らない。

### 4.3 dump 取得

`pg_dump` は PostgreSQL accessory コンテナ内のコマンドを使用する。

```bash
docker exec "$CONTAINER" pg_dump -U "$POSTGRES_USER" -Fc -d "$DB"
```

dump 形式は PostgreSQL custom format (`-Fc`) とする。

### 4.4 R2 への保存

VM ホストに `rclone` をインストールし、Cloudflare R2 用 remote を設定する。

dump は `/tmp` 配下の一時ファイルに保存し、`rclone copyto` で R2 にアップロードする。アップロード成功後、一時ファイルは削除する。

```bash
DUMP_FILE=$(mktemp "/tmp/${DB}_${STAMP}.XXXXXX.dump")
trap 'rm -f "$DUMP_FILE"' EXIT

docker exec "$CONTAINER" pg_dump -U "$POSTGRES_USER" -Fc -d "$DB" > "$DUMP_FILE"
rclone copyto "$DUMP_FILE" "${RCLONE_REMOTE}:${R2_BUCKET}/postgresql/${DB}_${STAMP}.dump" --s3-no-check-bucket
```

`rclone rcat` は標準入力からのストリーミングアップロードとなり、R2 との組み合わせで `501 NotImplemented` が発生する場合があるため、定常運用では使用しない。

## 5. スクリプト配置

### 5.1 リポジトリ内配置

バックアップスクリプトは以下に配置する。

```text
script/ops/backup_postgres_to_r2.sh
```

`script/ops/` は本番運用・保守用スクリプトの配置場所とする。将来、リストア検証やバックアップ検査を追加する場合も同ディレクトリへ配置する。

```text
script/ops/
  backup_postgres_to_r2.sh
  restore_postgres_from_r2.sh
  verify_postgres_backup.sh
```

### 5.2 VM ホスト上の配置

Kamal deploy 時に、リポジトリ内のスクリプトを VM ホスト上の固定パスへコピーする。

想定配置:

```text
<BACKUP_DEPLOY_DIR>/backup_postgres_to_r2.sh
```

cron はこの固定パスを実行する。

## 6. Kamal 連携

### 6.1 方針

Kamal は VM ホスト上の任意パスにスクリプトを配置して cron 登録する専用機能を持たないため、Kamal hook で `scp` / `ssh` を実行してスクリプトを配布する。

Kamal hook では以下のみを行う。

- VM ホスト上の配置ディレクトリを作成する。
- `script/ops/backup_postgres_to_r2.sh` を VM ホストへコピーする。
- 実行権限を付与する。

cron 登録・変更は hook では行わない。deploy のたびに crontab を書き換えると、運用上の意図しない変更や手動調整の上書きにつながるためである。

### 6.2 post-deploy hook 例

```sh
#!/usr/bin/env sh
set -eu

HOST="${SERVER_IP:?SERVER_IP is required}"
USER="${SSH_USER:?SSH_USER is required}"
REMOTE_DIR="${BACKUP_REMOTE_DIR:?BACKUP_REMOTE_DIR is required}"
SCRIPT="backup_postgres_to_r2.sh"

ssh "$USER@$HOST" "mkdir -p '$REMOTE_DIR'"
scp "script/ops/$SCRIPT" "$USER@$HOST:$REMOTE_DIR/$SCRIPT"
ssh "$USER@$HOST" "chmod 0750 '$REMOTE_DIR/$SCRIPT'"
```

上記を `.kamal/hooks/post-deploy` として配置する場合、hook 自体にも実行権限を付与する。

```bash
chmod +x .kamal/hooks/post-deploy
```

## 7. 認証情報

### 7.1 R2 認証

`rclone` の R2 認証情報は VM ホスト上で管理する。

推奨:

- `SSH_USER`で指定する運用ユーザーで `rclone config` を実行し、`RCLONE_REMOTE`で指定するremoteを作成する。
- cron も同じ運用ユーザーのcrontabに登録する。

確認:

```bash
rclone config file
rclone lsd r2:
```

root のcrontabから実行する場合、運用ユーザーの rclone 設定が読まれない可能性があるため、`--config` で設定ファイルを明示する。

```bash
rclone --config "/home/${SSH_USER}/.config/rclone/rclone.conf" copyto ...
```

### 7.2 DB 認証

`pg_dump` は PostgreSQL accessory コンテナ内で実行する。PostgreSQLユーザーは`POSTGRES_USER`環境変数から取得する。

```bash
pg_dump -U "$POSTGRES_USER" -Fc -d tech_notes_production
```

パスワード要求が発生する場合は、VM ホスト側に平文パスワードを置くのではなく、Docker exec 実行時の環境や `.pgpass` の扱いを別途検討する。

## 8. 保持期間

R2 上のバックアップ保持期間は 30 世代または約 30 日を基本とする。

保持期間の削除は、可能であれば R2 側の lifecycle rule で管理する。スクリプト側で削除処理を実装する場合は、誤削除を避けるため prefix を限定する。

推奨 prefix:

```text
${RCLONE_REMOTE}:${R2_BUCKET}/postgresql/
```

ファイル名:

```text
{db_name}_{YYYYmmdd_HHMMSS}.dump
```

例:

```text
tech_notes_production_20260702_030000.dump
```

## 9. ログ・監視

cron の標準出力・標準エラーはログファイルへ追記する。

```cron
0 3 * * * <BACKUP_DEPLOY_DIR>/backup_postgres_to_r2.sh >> /var/log/tech_notes_backup.log 2>&1
```

最低限、以下を確認できること。

- バックアップ開始時刻
- 対象 DB
- R2 保存先
- 成功 / 失敗
- DB コンテナが見つからない場合のエラー
- `pg_dump` または `rclone` 失敗時の非ゼロ終了

スクリプトでは `set -euo pipefail` を使用し、`pg_dump` 失敗時に `rclone` 側だけ成功扱いになることを避ける。

## 10. リストア検証

バックアップ運用開始後、少なくとも一度は別環境または一時 DB へリストアできることを確認する。

custom format dump のリストアには `pg_restore` を使用する。

```bash
pg_restore -U "$POSTGRES_USER" -d tech_notes_production_restore backup.dump
```

本番 DB へ直接リストアする手順は、誤操作時の影響が大きいため、別途 `restore_postgres_from_r2.sh` またはリストア手順書として定義する。

## 11. 非採用案

### 11.1 Rails web コンテナ内で定期実行

Rails web コンテナへ `pg_dump` / `rclone` を追加し、`kamal app exec` や Rails job からバックアップする案は採用しない。

理由:

- Rails アプリケーションイメージが重くなる。
- アプリケーション実行責務と運用バックアップ責務が混ざる。
- 1GB RAM 構成では不要なメモリ使用を避けたい。

### 11.2 backup 専用 Kamal role / cron コンテナ

Kamal の cron role を追加し、常駐 cron コンテナからバックアップする案は現時点では採用しない。

理由:

- 1GB RAM の単一 VM では、常駐コンテナ追加のメリットよりリソース消費の懸念が大きい。
- ホスト cron で同等の運用がより軽量に実現できる。

### 11.3 手元 PC からの定期実行

手元 PC から `kamal accessory exec db "pg_dump ..."` を実行し、R2 へアップロードする案は定期運用として採用しない。

理由:

- 手元 PC の起動状態・ネットワーク状態に依存する。
- 自動バックアップとしての信頼性が低い。

手動バックアップや検証用途では使用してよい。
