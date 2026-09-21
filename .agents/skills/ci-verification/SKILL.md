---
name: ci-verification
description: PRブランチやmainへのpush後にGitHub ActionsのCI結果を確認し、失敗時はログから原因を特定して最小修正・ローカル検証・プッシュを繰り返す。通過までループし日本語で報告する。CI確認、CI失敗対応、CI通過確認に使用する。
---

PRブランチまたは `main` へ `git push` した後は、必ずこのスキルの手順に従いCIの結果を確認すること。

## 前提

- CIは `.github/workflows/ci.yml` で定義され、**`pull_request` と `main` への `push` の両方**で実行される
- ジョブ構成（2026年9月時点）:
  - `scan_ruby`: `bin/brakeman --no-pager`、`bin/bundler-audit`
  - `scan_js`: `bin/importmap audit`
  - `lint`: `bin/rubocop -f github`
  - `test`: `bin/rails db:test:prepare test`
  - `system-test`: `bin/rails db:test:prepare test:system`（失敗時は `tmp/screenshots` をartifactに保存）
- ワークフローに paths フィルタはないため、**docs のみの変更でも全ジョブが実行される**。軽量扱いにはならない
- CI外のため必要に応じてローカルで実施するもの: SQLite／PostgreSQL 両アダプタの互換確認、Dockerイメージ／Kamal設定の検証（`deploy` スキル参照）。Sorbet（`bundle exec srb tc`）もCIには含まれないため、typedなRuby変更時はローカルで実施する

## ワークフロー

```
git push 完了（PRブランチ or main）
  ↓
CI確認（PRブランチ: gh pr checks / main: gh run list --branch main）
  ↓
完了まで待機（ポーリング）
  ↓
成功 → ユーザーに報告 → 終了
  ↓
失敗 → 失敗ログ取得 → 原因分析 → 最小修正 → ローカル検証 → コミット・プッシュ ↺
```

## フェーズ1: CI状態の確認

### 1.1 実行の特定

PRブランチへプッシュした場合:

```bash
gh pr checks <PR番号>
```

またはブランチ指定で確認する場合:

```bash
gh run list --branch <ブランチ名> --limit 5 --json databaseId,headSha,status,conclusion,event
```

`main` へプッシュした場合:

```bash
gh run list --branch main --limit 1 --json databaseId,headSha,status,conclusion,event
```

`headSha` がプッシュしたコミットと一致することを確認する。まだ実行が登録されていない場合は数秒待って再取得する。

### 1.2 完了までポーリング

```bash
sleep 60 && gh run list --branch <ブランチ名> --limit 1 --json databaseId,headSha,status,conclusion
```

`status` が `completed` になるまで、目安として60〜90秒間隔・最大10回（約10〜15分）再試行する。`test`・`system-test` を含むため実行時間が長い場合がある。進行状況は `gh run view <run-id>` で確認できる。

完了したら `conclusion` を判定する:

- `success` → フェーズ2へ
- `failure` / `cancelled` / `timed_out` → フェーズ3へ

## フェーズ2: 成功時の処理

1. ユーザーにCI通過を報告する（**報告は日本語で行う**。中国語など他言語を混入させない）
2. PRが存在する場合はPRのURLを添える。上位フローでcodex-review（レビュー依頼・コメント待機・指摘対応・マージ）が続く場合は、終了せずそのスキルへ進むこと

報告例:

```
CIが通過しました（ブランチ: <ブランチ名>）。
run: https://github.com/hiroeorz/tech_notes/actions/runs/<run-id>
```

## フェーズ3: 失敗時の自動修正ループ

`conclusion` が `success` 以外の場合、自動修正ループに入る。

### 3.1 失敗ログの取得

```bash
gh run view <run-id> --log-failed
```

失敗したジョブ・ステップ名を特定する（`scan_ruby`、`scan_js`、`lint`、`test`、`system-test` と各ステップ名）。

### 3.2 原因分析

失敗ログから以下を特定する:

- **失敗したジョブ・ステップ**: 上記のいずれか
- **失敗の直接原因**: エラーメッセージ、スタックトレース、指摘されたファイルと行番号
- **修正方針**: どのファイルをどう修正すればよいか

### 3.3 修正の実施

原因に基づいてコードを修正する。修正は以下の原則に従う:

- **最小限の修正**: CI失敗の原因だけを修正し、不要な変更を加えない
- **既存パターンの尊重**: 既存のコーディングパターンに従う
- **ローカル検証**: 修正後にローカルで該当するチェックを実行し、通過することを確認してからプッシュする

各CIジョブに対応するローカル検証コマンド:

| CIジョブ（ステップ） | ローカル検証コマンド |
|---|---|
| `scan_ruby`（Rails静的解析） | `bin/brakeman --no-pager` |
| `scan_ruby`（Gem脆弱性） | `bin/bundler-audit` |
| `scan_js` | `bin/importmap audit` |
| `lint` | `bin/rubocop`（CIでは `bin/rubocop -f github`） |
| `test` | `bin/rails db:test:prepare test`（関連のみなら `bin/rails test <ファイル>`） |
| `system-test` | `bin/rails test:system`（関連のみなら対象のシステムテストを指定） |

CI外で必要に応じローカル実施するもの:

- SQLite／PostgreSQL 互換確認（マイグレーション変更時。両アダプタで動作確認）
- Dockerイメージ／Kamal設定の検証（`deploy` スキル参照）
- `bundle exec srb tc`（typedなRuby変更時。CIには含まれない）
- 変更内容に応じた使い分けは `.agents/skills/code-change-verification/SKILL.md` に従う

### 3.4 コミット・プッシュ

修正がローカルで通過したら、コミット前に `.agents/skills/security-check/SKILL.md` の手順に従い機密情報スキャンを実行すること（コミットより前に実行し、🔴 CRITICAL または 🟠 HIGH があれば中断する）。その後コミットしてプッシュする:

```bash
git add <該当ファイル>
git commit -m "fix: <失敗内容の概要>

- 原因: <原因>
- 修正: <修正内容>"
git push origin <ブランチ名>
```

PRブランチの修正はそのままPRブランチへプッシュする。`main` への直接プッシュで失敗した場合は `main` へプッシュし直す。

### 3.5 再確認

プッシュ後、フェーズ1に戻ってCIを再確認する。PRブランチの場合は `gh pr checks <PR番号>` または `gh run list --branch <ブランチ名>`、通過するまでループする。

## フェーズ4: 自動修正不可の処理

以下の場合は自動修正を中断し、ユーザーに報告して指示を仰ぐ:

- 同一のエラーが3回連続で再発する場合
- CIインフラ自体の問題（GitHub Actionsの障害、runnerの問題、利用枠枯渇等）と判断される場合
- 修正方針が不明で推測による修正が危険な場合
- ローカルで再現できず原因が特定できない場合

報告内容:

- 失敗したジョブ・ステップ名とエラーメッセージ
- 試行した修正内容と結果
- ユーザーに求める対応（判断・手動修正・設定変更等）

## 注意事項

- CI確認は push の**直後に必ず**実行すること。プッシュして終了ではなく、CI結果まで責任を持つ
- CI失敗時の自動修正は、`bug-fix` スキルのワークフローに準じて行う（原因特定 → 修正方針 → 修正 → 検証）
- 修正コミットのメッセージは日本語で、`fix:` プレフィックスを付ける
- コミット前の機密情報スキャンは必須（コミットより前に実行し、CRITICAL／HIGHがあれば中断すること）
- CI待機中にユーザーへ進捗を報告する必要はない。通過または失敗確定時に報告する
- `git reset --hard`、`git clean`、force push、履歴書き換えは実行しない
