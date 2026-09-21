---
name: deploy-request
description: ユーザーが「デプロイしたい」「デプロイして」「デプロイ手順」「deploy したい」と言ったときに、対象リビジョンと検証状態を確認し、ユーザー自身がWSL側で実行する kamal デプロイ／ロールバックのコマンドを日本語で提供する。エージェントはデプロイを実行しない。Use ONLY when ユーザーからデプロイ実行の明示的な依頼がある場合。
---

# デプロイ手順の提示（deploy-request）

ユーザーの「デプロイしたい」に対し、**エージェントは実行せず、コマンドの提示のみ**を行う。デプロイの実行は環境変数が設定されたユーザーのWSLシェルで行う（エージェント実行環境のサンドボックスには `kamal` と環境変数・シークレットがないため実行できない）。運用正本は `docs/deployment.md`、詳細手順は `.agents/skills/deploy/SKILL.md`。

## 手順

### 1. 対象と検証状態の確認

```bash
git rev-parse HEAD           # 対象の完全SHA（40桁）
git status --short           # working tree が clean であること
git log --oneline origin/main..HEAD   # 未プッシュコミットの有無
```

- 対象は単一本番のみ（staging はない）。初回デプロイは `kamal setup`、通常は `kamal deploy`
- `main` の直近CIが成功していることを確認する（`gh run list --branch main --limit 1`。詳細は `.agents/skills/ci-verification/SKILL.md`）
- 未検証のリビジョン（ローカルテスト未実施、main CI未通過、未マージ）の場合は、その旨を明示してユーザーの判断を仰ぐ

### 2. 提示するコマンド（WSL側）

前提: `IMAGE`・`SERVER_IP`・`REGISTRY_USERNAME`・`SSH_USER`・`POSTGRES_*`・`APP_HOST`・`KAMAL_REGISTRY_PASSWORD`・`RAILS_MASTER_KEY` 等が設定済み、Docker 起動済み、`config/master.key` あり。値は表示・記録しない。

```bash
cd <tech_notes のディレクトリ>
git fetch origin && git checkout main && git pull --ff-only
git rev-parse --short HEAD   # 対象SHAと一致すること

# 事前確認（値は表示されない）
for v in IMAGE SERVER_IP REGISTRY_USERNAME SSH_USER POSTGRES_USER APP_HOST \
  POSTGRES_PASSWORD KAMAL_REGISTRY_PASSWORD RAILS_MASTER_KEY ADMIN_EMAIL ADMIN_PASSWORD; do
  [ -n "${!v:-}" ] && echo "$v=set" || echo "$v=MISSING"
done
ssh -t "$SSH_USER@$SERVER_IP" "docker --version && docker ps --format '{{.Names}}'"

# 現行バージョン（ロールバック候補）を控える
kamal app details

# デプロイ
kamal deploy

# デプロイ後確認
kamal app details
kamal accessory details db
kamal app logs --since 5m
curl -I "https://$APP_HOST/"
curl -s -o /dev/null -w "%{http_code}\n" "https://$APP_HOST/up"   # 200 を期待
```

- PRブランチのリビジョンを先に確認したい場合は、`git checkout <ブランチ名>` してから `kamal deploy` する（本番反映の標準はマージ後の main）。未レビューのリビジョンを本番へ出す場合はそのリスクを添える
- 対象リビジョンにDBマイグレーションや破壊的変更がある場合は、事前に手動バックアップ（`kamal app exec --reuse "script/ops/backup_postgres_to_r2.sh"`）を案内する

### 3. 失敗時の案内

- ヘルスチェック成功まで旧コンテナが稼働継続する（影響は限定的）
- `kamal app logs` / `kamal accessory logs db` で原因を確認
- 切り戻し: `kamal rollback <事前に控えたSHA>`（Docker Hub に旧イメージが残っている場合のみ）
- 原因がコード起因か環境起因（接続・DNS・秘密値不足）かを切り分け、環境起因をコード修正で解消しようとしない

### 4. 出力の確認と報告

ユーザーから共有された出力（`kamal deploy` の結果、`app details`、`/up` のHTTPステータス等）を確認し、異常の有無・ロールバック可否・残課題を日本語で報告する。秘密値は必ず伏せる。
