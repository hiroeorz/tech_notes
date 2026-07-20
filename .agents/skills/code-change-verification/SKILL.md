---
name: code-change-verification
description: Ruby、Rails、Stimulus、importmap、テスト、ビルド設定に変更があった場合に、このリポジトリで必要な検証を変更内容に応じて実行し、結果と未実行理由を報告する。
---

# コード変更検証

コード、テスト、JavaScript、依存関係、ビルド・テスト設定に変更がある場合に使用する。ドキュメントのみの変更では、内容に実行手順や設定変更が含まれない限り使用しない。

## 基本方針

- 変更ファイルを最初に確認し、必要な検証だけを選択する。
- 変更内容に直接関係するテストを先に実行し、最後に必要な全体検証を実行する。
- 失敗したコマンドを黙って省略しない。失敗内容、影響、次の対応を報告する。
- 実行環境や依存関係の不足で実行できない場合は、未実行理由を明記する。
- このスキルは検証を担当する。失敗を修正する場合は、元の作業スキルまたは不具合修正の手順へ戻る。
- コミット前の機密情報スキャンは `security-check` スキルの責務であり、このスキルで代替しない。

## 変更分類

`git diff --name-only` と差分の内容から、次の分類を行う。複数の分類に該当する場合は、検証を組み合わせる。

### Ruby / Rails

次のいずれかに該当する変更:

- `app/**/*.rb`
- `config/**/*.rb`、`config/routes.rb`
- `db/**/*.rb`
- `lib/**/*.rb`
- `test/**/*.rb`
- `Gemfile`、`Gemfile.lock`

実行する検証:

1. 変更内容に関連するテスト
2. Rubyファイルを変更した場合は `bin/rubocop`（可能なら変更ファイルを対象にした後、最終確認で全体）
3. `# typed: true` 以上のRubyファイルを変更した場合は `bundle exec srb tc`
4. 認証、入力処理、Markdown、公開処理、SQL、Active Storage、設定を変更した場合は `bin/brakeman --no-pager`

### JavaScript / importmap

次のいずれかに該当する変更:

- `app/javascript/**/*`
- `config/importmap.rb`

実行する検証:

1. importmapのpinや依存関係を変更した場合は `bin/importmap audit`
2. Stimulusの動作、イベント、フォーム、テーマ、画面表示を変更した場合は関連するシステムテスト
3. 対応するシステムテストがない場合は、テスト不足として報告する

このリポジトリにはNode.jsのビルド・Lintツールチェーンを導入しない。`npm`、`pnpm`、`yarn`のコマンドを追加で実行したり、依存関係を導入したりしない。

### 依存関係 / ビルド・CI設定

- `Gemfile` または `Gemfile.lock` の変更: `bin/bundler-audit` と関連テスト
- `config/ci.rb`、`bin/*`、Docker、Kamal、CI設定の変更: 変更対象のコマンドを実行できる範囲で確認し、少なくとも関連する静的解析・テストを実行
- `db/migrate/*` または `config/database.yml` の変更: `bin/rails db:prepare` と関連テスト。SQLiteとPostgreSQLの差異がある場合は、両アダプタでの確認方法を報告

## 検証レベル

### 関連検証

変更に直接関係するテストを実行する。テストファイルが明らかな場合は単一ファイルまたは名前指定で実行する。既存の統合テストにアサーションを追加した場合は、関連するテスト名を指定する。

### 全体検証

次の場合は、関連検証に加えて全体検証を実行する。

- 実行時コードを変更した
- 認証、公開画面、Markdown、DB、ジョブ、設定など横断的な影響がある
- 依存関係、テスト設定、ビルド設定を変更した
- 作業の完了確認を行う段階に入った

実行順序:

```bash
bundle exec srb tc              # typedなRuby変更がある場合
bin/rubocop
bin/brakeman --no-pager         # セキュリティ関連のRuby変更がある場合
bin/bundler-audit               # Gemfile系の変更がある場合
bin/importmap audit             # importmap系の変更がある場合
bin/rails test
```

UIや画面挙動を変更した場合は、全体検証の後に次も実行する。

```bash
bin/rails test:system
```

システムテストがブラウザ、Chromium、Chromedriver、ローカルソケットなどの環境要因で実行できない場合は、失敗を修正済みとして扱わず、未実行または環境起因の失敗として報告する。

## 完了報告

以下の形式で、コマンドごとに結果を報告する。

```text
## コード変更検証

### 変更分類
- Ruby / Rails: 実施・対象なし
- JavaScript / importmap: 実施・対象なし
- 依存関係 / CI設定: 実施・対象なし

### 実行結果
- ✅ / ❌ / ⏭️ コマンド — 結果または未実行理由

### 残課題
- 失敗、未実行、テスト不足、環境依存があれば記載
```

すべての必要な検証が成功した場合のみ、変更を検証済みとして扱う。テストやシステムテストを実行していない場合は、その理由を必ず残す。
