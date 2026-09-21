---
name: save-memory-knowhow
description: 作業で得た再利用可能なノウハウを ~/ai-memory（hiroeorz/ai-memory）へ保存する。feature-implementation / bug-fix / rails-upgrade / ruby-upgrade の完了後フロー、苦戦した点・試行錯誤の記録、ai-memory への追記を依頼された場合に使用する。
---

# ノウハウ保存（ai-memory）

作業中の苦戦・試行錯誤から再利用可能な知見を `~/ai-memory` に追記する。`~/ai-memory` はこのリポジトリとは別の Git リポジトリ（`git@github.com:hiroeorz/ai-memory.git`）で、`README.md` にエイリアス一覧、`opencode.json` に opencode の `references` 定義がある。

## 保存するかどうかの判断

- **保存する**: 再発しそうな罠、原因特定に時間がかかった事象、コマンド・設定の落とし穴、環境起因の対処、判断基準が非自明だったもの
- **保存しない**: 単純な作業記録、一時的な状況、既存メモと重複する内容、このアプリ固有の内容（モデル名・テーブル名・画面名・機能名・デプロイスクリプト実装など）
- アプリ固有の知見はこのリポジトリ内（`docs/`、`AGENTS.md`、リポジトリ内 `ai-memory/` 等）へ置く。`~/ai-memory` には一般化した共有ノウハウだけを書く

## 手順

1. 既存メモを確認する（重複を避ける）

   ```bash
   ls ~/ai-memory
   grep -ril "<キーワード>" ~/ai-memory --include="*.md"
   ```

2. カテゴリを選ぶ（`~/ai-memory/README.md` の「カテゴリ」参照）
   - `langage/ruby/`（`rails/`・`test/`）、`langage/javascript/`、`langage/html/`、`langage/css/`
   - `connection/`、`operation/`、`github/`、`container/docker/`、`database/postgresql/` など

3. 1ファイル＝1トピックで作成する（ファイル名は snake_case。既存メモの書式に合わせる）

   ```markdown
   # <タイトル>

   ## 事象

   - ...

   ## 対処

   - ...
   ```

4. `~/ai-memory/README.md` の references 登録表に「エイリアス / ファイル / いつ使うか」を追記する

5. `~/ai-memory/opencode.json` の `references` にエイリアス・`path`・`description` を追記し、JSON を検証する

   ```bash
   python3 -m json.tool ~/ai-memory/opencode.json > /dev/null && echo "JSON OK"
   ```

6. 反映には opencode の再起動が必要な旨を報告する

7. コミット・プッシュはユーザーの明示指示がある場合のみ行う（別リポジトリのため、このリポジトリの作業ツリーには触れない）

   - 今回追記したファイル（新しいメモ・`README.md`・`opencode.json`）**だけ**を明示的にステージする。`git add -A` は使わない
   - 無関係な未コミット変更・削除が残っている場合はステージせず、内容をユーザーに確認する
   - コミット前に、ステージ対象のファイルを直接読んで機密情報・個人情報・アプリ固有情報が含まれていないか確認する（`.agents/skills/security-check/SKILL.md` の確認項目に準じ、🔴 / 🟠 相当があればコミットを中断する）

   ```bash
   git -C ~/ai-memory status --porcelain
   git -C ~/ai-memory add <新しいメモ> README.md opencode.json
   git -C ~/ai-memory diff --cached --stat
   git -C ~/ai-memory commit -m "ノウハウ追加: <概要>"
   git -C ~/ai-memory push origin main
   ```

## 注意

- `cd ~/ai-memory` してから git を実行しない（カレントリポジトリの誤操作防止）。必ず `git -C ~/ai-memory` を使う
- 秘密値・APIキー・実IP・本番ドメイン・個人情報を書かない
- force push・`git reset --hard`・`git clean`・履歴書き換えは禁止
- opencode.json の `references` は起動時に読み込まれるため、追記しただけでは現在のセッションには反映されない
