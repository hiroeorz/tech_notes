---
name: code-change-verification
description: Ruby、Rails、Stimulus、importmap、テスト、ビルド設定に変更があった場合に、このリポジトリで必要な検証を変更内容に応じて実行し、結果と未実行理由を報告する。
---

# コード変更検証

コード、テスト、JavaScript、依存関係、ビルド・テスト設定に変更がある場合に使用する。ドキュメントのみの変更では、内容に実行手順や設定変更が含まれない限り使用しない。

本スキルが実行されたら、定義済みのサブエージェントを積極的に使うこと。
特に
* 設計： solution-architect
* コードレビュー: code-reviewer
* データベースレビュー : database-reviewer
* ドキュメント更新 : documentation-manager
* Railsコーディング : rails-implementer
* フロントエンドコーディング : frontend-implementer
* セキュリティレビュー : security-auditor
* テスト : test-engineer
* git, github 操作 : repository-operator
* 国際化・多言語化 : internationalization-implementer
* 翻訳完全性チェック : translation
* 画面案・スクリーンショットの参照解釈 : visual-reference-analyzer

の使用を推奨する。
他のエージェントについても必要に応じて起動して作業を進めてください。

国際化・多言語化が必要な時は internationalization スキルを使用すること。
ユーザー向け文言、locale ファイル、ビュー、flash、バリデーション、メール、JavaScript を変更した後は translation スキルで翻訳完全性を確認し、抜けがなくなるまで翻訳を補完すること。

## 基本方針

- 変更ファイルを最初に確認し、必要な検証だけを選択する。
- 変更内容に直接関係するテストを先に実行し、最後に必要な全体検証を実行する。
- 同一の変更スナップショットに対して、各検証（静的解析・全体テスト・システムテスト）はそれぞれ1回だけ実行する。完了報告済みの同一結果を理由なく再実行しない。コード・テスト・設定が変わった場合のみ該当検証を再実行する。ただし修正ラウンド（レビュー指摘対応・`fix:` コミット）中は変更に関連する検証のみを再実行し、全体テスト・システムテストは最終スナップショットで1回だけ実行する。
- 失敗時は原因を分類（コード起因／テスト起因／環境起因）して記録し、同じコマンドを無意味に繰り返さない。環境起因の失敗をコード修正で解消しようとしない。
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

### Markdown / 公開表示

次のいずれかに該当する変更:

- `app/models/markdown_renderer.rb`
- `app/helpers/posts_helper.rb`（`render_markdown` / `extract_headings`）
- 記事本文の表示に関わるビュー・ヘルパー
- `test/models/markdown_renderer_test.rb`

実行する検証:

1. 新しい HTML 要素や属性を扱う場合は `MarkdownRenderer` の許可リスト（`ALLOWED_TAGS` / `ALLOWED_ATTRIBUTES`）を更新しないと内容が黙って除去されるため、許可リストの更新と `test/models/markdown_renderer_test.rb` へのテスト追加を行う
2. 新たに Markdown を扱う箇所はコントローラーやビューから直接レンダリングせず `PostsHelper#render_markdown` / `#extract_headings` を使用する（公開記事のレンダリングと管理画面のライブプレビューの両方が単一レンダラーを経由する）
3. URL に `remote-state-architecture` が含まれる場合のカスタム図表（`diagram_markup`）の仕様を変更する場合は、レンダラーと対応する統合テストの両方を更新する
4. 変更内容に関連するモデルテスト・統合テストを実行する

### 依存関係 / ビルド・CI設定

- `Gemfile` または `Gemfile.lock` の変更: `bin/tapioca gem` で Gem RBI を更新し、`bundle exec srb tc`、`bin/bundler-audit`、関連テストを実行
- モデルやルーティングなど Rails DSL に由来する型情報の変更: `bin/tapioca dsl` で DSL RBI を更新し、`bundle exec srb tc` を実行
- `sorbet/**/*.rbi` の変更: `bundle exec srb tc` を実行し、生成RBIの場合は対応する Tapioca コマンドで再生成できることを確認
- `config/ci.rb`、`bin/*`、Docker、Kamal、CI設定の変更: 変更対象のコマンドを実行できる範囲で確認し、少なくとも関連する静的解析・テストを実行
- `db/migrate/*` または `config/database.yml` の変更: `bin/rails db:prepare` と関連テスト。開発・テストの SQLite と本番の PostgreSQL でアダプタ差があるため、双方での互換性または確認方法を報告

### インフラ / デプロイ設定

- `config/deploy.yml`、`config/postgres/init.sql`、`docs/deployment.md` の変更は同期して更新する。サービス名 `tech_notes` の一貫性（`deploy.yml`、accessory ホスト `tech_notes-db`、Active Storage ボリューム `tech_notes_storage`）を確認する
- シークレット（`RAILS_MASTER_KEY`、`POSTGRES_PASSWORD`、`ADMIN_PASSWORD` 等）は `.kamal/secrets` 経由で環境変数から注入し、生値をコミットしない

## 検証レベル

### 関連検証

変更に直接関係するテストを実行する。テストファイルが明らかな場合は単一ファイルまたは名前指定で実行する。既存の統合テストにアサーションを追加した場合は、関連するテスト名を指定する。

システムテストを変更・追加した場合は、関連ファイルを先に実行し、全量のシステムテストは最後に1回だけ実行する。

### 全体検証

次の場合は、関連検証に加えて全体検証を実行する。

- 実行時コードを変更した
- 認証、公開画面、Markdown、DB、ジョブ、設定など横断的な影響がある
- 依存関係、テスト設定、ビルド設定を変更した
- 作業の完了確認を行う段階に入った

同一の変更スナップショットに対して、静的解析・全体テスト・システムテストはそれぞれ1回だけ実行する。完了報告済みの同一結果を理由なく再実行せず、コード・テスト・設定が変わった場合のみ該当検証を再実行する。失敗時は原因を分類（コード起因／テスト起因／環境起因）して記録し、同じコマンドを無意味に繰り返さない。

実行順序:

```bash
bundle exec srb tc              # typedなRuby変更がある場合
bin/rubocop
bin/brakeman --no-pager         # セキュリティ関連のRuby変更がある場合
bin/bundler-audit               # Gemfile系の変更がある場合
bin/importmap audit             # importmap系の変更がある場合
bin/rails test
```

ユーザー向け文言、locale ファイル、ビュー、flash、バリデーション、メール、JavaScript を変更した場合は、`bin/rails test` の後に `.agents/skills/translation/SKILL.md` に従い、translation で翻訳完全性を確認する。未翻訳キー・直書き文言がなくなるまで繰り返し、関連テストを実行する。

UIや画面挙動を変更した場合は、全体検証の後に次も実行する。

```bash
bin/rails test:system
```

システムテストがブラウザ、Chromium、Chromedriver、ローカルソケットなどの環境要因で実行できない場合は、失敗を修正済みとして扱わず、未実行または環境起因の失敗として報告する。

全量のテストで今回の変更と無関係なテストが失敗した場合は、そのテストファイルを単独実行（必要に応じて失敗出力の `--seed` を指定）して切り分ける。単独で通過すれば環境起因（並列実行のリソース競合やブラウザの一時状態）として記録し、同一スナップショットで全量を再実行して成功を確認する。単独でも再現する場合はコード起因／テスト起因として修正対象にする。並列時のフレークと恒久的な失敗を混同し、無関係なコードを修正しない。

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
