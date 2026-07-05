---
name: security-check
description: git commit 前にリポジトリ全体の機密情報漏洩を監査する。ハードコードされた公開IP・ドメイン・APIキー・個人名・環境変数フォールバック値などを検査する。
---

リポジトリ内の機密情報漏洩を監査するよう指示された場合、または `git commit` の実行前に、このスキルを使用すること。

## 確認方法

**grep や ripgrep などのパターンマッチ検索は補助的にのみ使用すること。** 最終的な判定は、各ファイルを直接開いて中身を読むことで行う。自動検索ではコメントアウトされた値、テンプレート内の埋め込み、暗黙的なデフォルト値などを見落とすリスクがあるため、**すべてのファイルを人手で確認**することを原則とする。

## 確認項目

**すべての追跡ファイル**（`vendor/`, `.bundle/`, `log/`, `tmp/`, `storage/`, `Gemfile.lock`, `db/schema.rb` は除外）を以下の観点で検査する。

### 1. ハードコードされた公開IPアドレス

設定ファイル（特に `config/deploy.yml`, `.kamal/hooks/`, `docs/`）で、プライベートIP範囲外のIPアドレスが直書きされていないか確認する。
プライベートIP範囲（`127.0.0.0/8`, `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`）は許容する。

### 2. ハードコードされたドメイン名

`config/deploy.yml`, `config/environments/production.rb`, `docs/` などに本番ドメイン名が直書きされていないか確認する。

### 3. APIキー・トークン・パスワードの生値

以下のパターンに合致する値がコード中に存在しないか確認する。
- `ghp_`, `gho_`, `github_pat_`（GitHub トークン）
- `sk-`（OpenAI キー）
- `AKIA`（AWS アクセスキー）
- `xox[baprs]-`（Slack トークン）
- `-----BEGIN.*KEY-----`（秘密鍵・証明書）

### 4. 実ユーザー名・個人名のハードコード

`config/deploy.yml`, `config/database.yml`, `script/ops/*.sh`, `.kamal/hooks/*`, `Dockerfile` などに、開発者や運用者の実ユーザー名（例: `hiroe`）、個人を特定できるハンドル名が直書きされていないか確認する。SSHユーザー名、DBユーザー名、Docker Hubユーザー名、コンテナイメージ名などが該当する。これらは環境変数化すべき情報であり、リポジトリクローンですべての閲覧者に知られることになる。

### 5. 環境変数のフォールバック値としてのハードコード

`config/database.yml`, `script/ops/*.sh`, `.kamal/hooks/` などで、`ENV.fetch("VAR", "ハードコードされた値")` にプレースホルダではない実際の値が指定されていないか確認する。

### 6. git に追跡された `.env` ファイルや `.key` ファイル

`git ls-files | grep -E '\.env|\.key|secret|credential|\.pem|\.crt'` を実行し、機密ファイルが誤って追跡されていないか確認する。

### 7. ファイル単位の直接確認

以下の高リスクカテゴリに該当する**すべてのファイル**を開き、内容を直接読んで確認する。

| カテゴリ | ファイル |
|----------|---------|
| デプロイ設定 | `config/deploy.yml`, `.kamal/secrets`, `.kamal/hooks/*` |
| データベース設定 | `config/database.yml`, `config/storage.yml` |
| 環境設定 | `config/environments/production.rb` |
| スクリプト | `script/ops/*.sh`, `bin/docker-entrypoint` |
| CI / Docker | `.github/`, `Dockerfile`, `.dockerignore` |
| インフラドキュメント | `docs/deployment.md`, `docs/backup-requirements.md` |
| シードデータ | `db/seeds.rb` |
| デフォルト値を持つモデル | `app/models/site_setting.rb` |
| テストファイル | `test/**/*.rb`（テストデータを装った実際の認証情報がないか確認） |

### 8. 問題としないもの（スキップしてよい）

- `@example.com` ドメインのメールアドレス（RFC 2606 予約済み、サンプル/テスト用として安全）
- `password123` のようなテスト用パスワード（テストフィクスチャのみ）
- ブログ設定として意図された公開SNSアカウント名
- 暗号化済み credentials ファイル（`config/credentials.yml.enc`）
- `$CLOUDFLARE_R2_SECRET_ACCESS_KEY` のような環境変数**参照**（変数名であって値ではない）
- ブログのシード記事本文中に含まれるサンプルTerraform / コードスニペット

## レポート形式

問題を発見した場合は、以下の構造でレポートを出力する。

```
## Security Check Report

### 🔴 CRITICAL
- {説明} — {ファイル:行}

### 🟠 HIGH
- {説明} — {ファイル:行}

### 🟡 MEDIUM
- {説明} — {ファイル:行}
```

問題がない場合は、以下を出力する。

```
✅ セキュリティチェック合格 — 機密情報の漏洩は検出されませんでした。
```

## 実行タイミング

このチェックは `git commit` の**実行前に必ず**実施すること。🔴 CRITICAL または 🟠 HIGH の問題が見つかった場合はコミットを**中断し**、発見内容を報告してユーザーの指示を待つこと。
