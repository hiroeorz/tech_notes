# AGENTS.md

このファイルは本リポジトリで作業するAIエージェント（および人間）のためのガイドです。複数のファイルを読まなければ推測できない、暗黙的な規約やワークフローを記録します。

## コミュニケーション

- すべてのユーザー向けメッセージ（説明・質問・要約・コミットメッセージ案を含む）は**日本語**で記述すること。
- コミットメッセージは**日本語**で記述すること。

## スタック

- Rails 8.1 on Ruby 4.0.5（`rbenv`、`.ruby-version` でバージョン固定）
- Bundle path は `vendor/bundle`（グローバルではない）— `.bundle/config` で設定。`bundle install` は gems をローカルに保持する。
- フロントエンド: importmap + Stimulus、Node.js ツールチェーンなし。JS は `app/javascript/` に配置、pinning は `config/importmap.rb`。
- Markdown はサーバーサイドで `MarkdownRenderer`（`app/models/markdown_renderer.rb`）によりレンダリング。`commonmarker` + Nokogiri ベースのサニタイズを使用。公開記事のレンダリングと管理画面のライブプレビューの両方がこの単一レンダラーを経由する。新たに markdown を扱う箇所は `PostsHelper#render_markdown` / `#extract_headings` を使用すること — コントローラーやビューから直接レンダリングしない。

## データベース（アダプタ分割 — 重要）

- **開発・テストは SQLite**（`storage/*.sqlite3`）。
- **本番は PostgreSQL**（Kamal accessory、同一クラスタ上に4つの論理DB: `tech_notes_production{,_cache,_queue,_cable}`）。初期化SQLは `config/postgres/init.sql`。
- `config/database.yml` は本番用に環境変数（`DB_HOST`, `DB_PORT`, `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB{,_CACHE,_QUEUE,_CABLE}`）を読む。
- **SQLite固有またはPostgreSQL固有の機能を使うマイグレーションは、両方のアダプタで動作することを確認してから追加すること** — dev/test は SQLite、production は PostgreSQL。
- Solid Cache / Queue / Cable は本番では `cache` / `queue` / `cable` ロールに配線される（`config/{cache,queue,cable}.yml`）。
- `bin/rails db:prepare` が正規の準備コマンド — 本番起動時に `bin/docker-entrypoint` から呼ばれる。ローカルでもこれを使うこと。

## テスト

- 単一の統合テストスイートがアプリ全体をカバー: `test/integration/blog_flow_test.rb`（ほとんどのアサーションはここに）。モデルテストは小さく的を絞っている。
- テストは `RAILS_ENV=test` の **SQLite** で実行 — 外部サービス不要。
- 全テスト実行: `bin/rails test`
- システムテスト実行: `bin/rails test:system`
- 単一ファイル: `bin/rails test test/integration/blog_flow_test.rb`
- 名前指定: `bin/rails test test/integration/blog_flow_test.rb -n test_admin_can_sign_in_and_view_management_pages`
- システムテストは `test/system/` にあり、ブラウザ駆動のJavaScript動作をカバー。Chromium/Chrome と Chromedriver が必要。サンドボックス環境では Capybara/Selenium がローカルソケット通信を使うため、サンドボックス外で実行する必要がある場合がある。
- `parallelize(workers: :number_of_processors)` が有効 — 失敗が混ざることがあるので、安定した順序が必要な場合は失敗出力の `--seed` を指定して再実行する。
- Fixtures は最小限（`test/fixtures/files/` には Active Storage のバリデーションテスト用の `not-image.txt` のみ）。テストは `setup` でレコードを構築する。
- Admin パスワードのハッシュ化はカスタム実装（`AdminUser.digest_password`、ユーザーごとの salt + secret_key_base）。テストで `AdminUser` を作成する際は `password_salt:` と `password_digest: AdminUser.digest_password(...)` を渡すこと — `password=` セッターは salt を再生成するためテストのセットアップでは使いづらい。

## 機能追加のワークフロー

- 機能追加は、要件整理、設計、実装、テスト実装、テスト実行、Rubocopなどのリンター実行の順で進める。
- UIや画面挙動を追加・変更する場合は、実装前に `docs/requirements.md` の該当セクションへ要件を追記または更新する。
- Ruby、テスト、JavaScript、importmap、依存関係、ビルド・テスト設定を変更した場合は、完了前に `.agents/skills/code-change-verification/SKILL.md` を使用し、変更内容に応じた検証を実行する。ドキュメントのみの変更では、実行手順や設定変更を含む場合を除き使用しない。
- 実装・設定・テスト・運用の変更で仕様書、README、デプロイ・バックアップ文書との同期が必要な場合は、`.codex/agents/documentation_manager.toml` の `documentation_manager` を起動する。監査のみの場合は先に差分と根拠を報告し、更新の明示委譲を受けてから編集する。

## スキルのトリガー条件

作業内容が複数の条件に該当する場合は、該当するスキルを組み合わせて使用する。特に、コード変更を伴う作業では、作業種別のスキルに加えて `code-change-verification` を使用する。

- **`feature-implementation`**: 新機能の追加、既存機能の仕様変更、画面・API・データモデルの機能拡張を依頼された場合。要件整理、設計、実装、テスト、全体チェック、コミット・PR作成までの手順として使用する。
- **`bug-fix`**: 不具合、エラー、期待動作との差異、再現可能な回帰の修正を依頼された場合。再現、原因調査、修正、回帰テスト、検証の手順として使用する。
- **`rails-upgrade`**: Railsのバージョンまたはパッチレベルを更新する場合。Rails本体、関連設定、互換性、依存Gemの影響を調査・修正・検証する手順として使用する。
- **`ruby-upgrade`**: Rubyのバージョンまたはパッチレベルを更新する場合。Ruby本体、`.ruby-version`、Gem、互換性、実行環境の影響を調査・修正・検証する手順として使用する。
- **`dependabot-pr`**: Dependabotが作成したPRの調査、依存関係更新の検証、マージ判断を行う場合。Dependabot以外の通常の依存関係更新には、変更内容に応じて `feature-implementation` または `bug-fix` と `code-change-verification` を使用する。
- **`deploy`**: `kamal deploy`、初回の `kamal setup`、本番デプロイ前の確認、デプロイ障害の調査、ロールバックを行う場合。デプロイ実行前に必ず使用する。
- **`deploy-request`**: ユーザーから「デプロイしたい」と依頼され、エージェントは実行せず、ユーザーがWSL側で実行するデプロイ／ロールバックのコマンド提示のみを行う場合。
- **`code-change-verification`**: Ruby、Rails、テスト、JavaScript、Stimulus、importmap、Gem依存関係、DB、CI、Docker、ビルド・テスト設定を変更した場合。変更内容に応じて関連テスト、Sorbet、Rubocop、Brakeman、bundler-audit、importmap audit、全テスト、システムテストを選択して実行する。ドキュメントのみの変更では、実行手順や設定変更を含む場合を除き使用しない。
- **`security-check`**: `git commit` を実行する前、またはリポジトリ内の機密情報漏洩を監査するよう依頼された場合。コミット前には必ず使用し、CriticalまたはHighの指摘があればコミットを中断する。
- **`issue-handling`**: GitHubのオープンIssueを確認・分類し、不具合は `bug-fix`、機能追加・仕様変更は `feature-implementation` で順次対応する場合。対応計画の承認後に1グループずつ対応する。
- **`codex-review`**: PR作成後にCodexへレビューを依頼し、指摘対応後にmainへマージして後片付けする場合。`feature-implementation` / `bug-fix` などの完了後フローから使用する。
- **`ci-verification`**: `main` へのpush後にGitHub ActionsのCI結果を確認し、失敗時は原因分析・最小修正・再プッシュのループを回す場合。CIは `main` へのpush時のみ実行されるため、PRブランチでは確認できない。
- **`documentation-authoring`**: 要件定義書、機能仕様書、設計書、運用手順書、README、利用者向けガイドなどの技術文書を新規作成・更新・レビューする場合。根拠の分類と最小差分で記述する。
- **`internationalization`**: Railsアプリの国際化・多言語化（ユーザー向け文言のI18n移行、locale切替、対象localeでの表示確認）を行う場合。
- **`translation`**: コード変更後に全localeの翻訳キー欠落や直書きのユーザー向け文言を検出し、抜けがなくなるまで翻訳を補完する場合。
- **`visual-adjustment`**: ブラウザでの画面の見た目を調整する場合。CSS・レイアウト・余白・色・フォント・テーマ・レスポンシブ崩れなどをデザイン要件と照合しながら修正する。
- **`save-memory-knowhow`**: マージ後のノウハウ保存、`~/ai-memory`（hiroeorz/ai-memory）への追記を行う場合。`feature-implementation` / `bug-fix` / `rails-upgrade` / `ruby-upgrade` の完了後フローから使用する。

## サブエージェントのトリガー条件

`.codex/agents/` と `.opencode/agents/` に定義されたサブエージェントは、作業内容が条件に該当し、親エージェントが明示的に委譲した場合に起動する。サブエージェントは担当範囲を越えて編集・コミット・プッシュ・PR操作を行わない。サブエージェントのモデル指定は原則なし（既定モデルを使用する）。画像の読解を行う `visual_reference_analyzer` のみ、画像解読に必要なモデルを指定している。

| サブエージェント | 起動条件 | 主な担当 |
|---|---|---|
| `solution_architect` | 新機能・大きな仕様変更の実装前で、設計案、影響範囲、DB変更、互換性、チケット分割の検討が必要な場合 | 読み取り専用の設計補佐 |
| `bug_investigator` | 不具合の原因調査、再現確認、ログ・履歴・コード追跡が必要な場合 | 読み取り専用の不具合調査 |
| `rails_implementer` | モデル、コントローラー、サービス、ジョブ、ルーティング、Markdown処理などRailsバックエンドの実装チケットを委譲する場合 | Railsバックエンド実装 |
| `frontend_implementer` | ERB、CSS、Stimulus、アクセシビリティ、レスポンシブ表示など公開・管理画面のUI変更チケットを委譲する場合 | フロントエンド実装 |
| `test_engineer` | 回帰テスト、単体・統合・システムテストの設計・追加・失敗解析を委譲する場合 | Minitestのテスト実装・検証 |
| `database_reviewer` | マイグレーション、DB設計、インデックス、データ整合性、SQLite／PostgreSQL互換性のレビューが必要な場合 | 読み取り専用のDBレビュー |
| `code_reviewer` | 実装差分の独立レビュー、バグ、回帰、設計不整合、テスト不足の確認が必要な場合 | 読み取り専用のコードレビュー |
| `security_auditor` | 認証認可、入力処理、XSS、CSRF、SQLインジェクション、SSRF、アップロード、機密情報、依存脆弱性の監査が必要な場合 | 読み取り専用のセキュリティ監査 |
| `documentation_manager` | 実装・設定・テスト・運用の変更に伴い、仕様書、README、デプロイ・バックアップ文書の同期や監査が必要な場合 | コードを根拠にしたドキュメント管理 |
| `repository_operator` | 親エージェントが明示的にGit／GitHub操作を割り当てた場合 | Git状態確認、ステージング、コミット、プッシュ、PR操作 |
| `release_operator` | 親エージェントが明示的にデプロイ、ロールバック、DB変更、コンテナ操作、リリース確認、GitHub操作を割り当てた場合 | Kamalによるリリース・運用 |
| `internationalization_implementer` | ユーザー向け文言のI18n移行、locale切替、関連テストの実装チケットを委譲する場合 | 国際化・多言語化の実装 |
| `translation` | 全localeの翻訳キー欠落や直書き文言の検出・補完を委譲する場合 | 翻訳完全性のチェック・補完 |
| `visual_reference_analyzer` | `docs/images/` などの見本画像を読み込み、再現可能な粒度の仕様レポートが必要な場合 | 読み取り専用の見本画像解析 |

サブエージェントの識別子は実行環境で表記が異なる。`.opencode/agents/` はハイフン表記（例: `bug-investigator`、`code-reviewer`）、`.codex/agents/` はアンダースコア表記（例: `bug_investigator`、`code_reviewer`）で定義されている。スキル本文中の表記が実行環境と異なる場合は、実行環境の定義に合わせて読み替えて task ツールに指定すること。

特に、`repository_operator` と `release_operator` による外部状態の変更は明示割り当てを必須とする。コミット前には `security-check` を実行し、`git reset --hard`、`git clean`、force push、履歴書き換え、無断マージは実行しない。

## リンター / 型チェック / セキュリティスキャン

- 型チェック: `bundle exec srb tc` で Sorbet の静的型検査を実行。`# typed: true` 以上のファイルでエラーがないことを確認する。`sorbet/rbi/gems/` はgit管理外のため、クリーンなチェックアウトでは先に `bin/tapioca gem` でgem RBIを生成する。
- スタイルは Rails Omakase 準拠: `bin/rubocop` で `rubocop-rails-omakase` 設定を実行。CI では `bin/rubocop -f github`。
- CI（`.github/workflows/ci.yml`）は `main` への push 時のみ実行され、単一ジョブ `ci` で Lint・gem RBI生成（`bin/tapioca gem`）・Sorbet 型チェック・全テスト（`bin/rails test` と `bin/rails test:system`）のみを順に実行する。PR ブランチでは実行されない。
- `bin/brakeman --no-pager`、`bin/bundler-audit`、`bin/importmap audit` は GitHub Actions では実行しない。セキュリティ関連の変更時などに `code-change-verification` スキルに従いローカルで実行する（`bin/ci` はこれらを含むローカルCIランナー）。

## Dependabot PR の処理

- Dependabot が起票した PR の処理は `.agents/skills/dependabot-pr/SKILL.md` の手順に従うこと。
- patch 更新は `.github/workflows/auto-merge-patches.yml` により PR の CI を待たずに自動マージされる（CI は `main` への push 時のみ実行されるため）。main の CI が唯一の自動検証であり、失敗時は通常フローで修正する。
- Dependabot 設定は `.github/dependabot.yml` にあり、Bundler と GitHub Actions を週次（金曜17:00 JST）で更新する。更新頻度や対象を変更する場合は、同スキルの提案内容を参照してユーザーと相談すること。

## コミット前のセキュリティチェック

- `git commit` を実行する**前に必ず** `.agents/skills/security-check/SKILL.md` の手順に従い、コミット対象の変更ファイルを対象とした機密情報スキャンを実行すること（リポジトリ全体のスキャンは明示的に指定された場合のみ）。
- 🔴 CRITICAL または 🟠 HIGH の指摘が見つかった場合は、**コミットを中断し**、発見内容をユーザーに報告して指示を仰ぐこと。
- 🟡 MEDIUM 以下の指摘のみの場合は、報告は行うがユーザーの判断でコミットを継続してよい。
- チェックで問題がなければ通常通りコミットを進めてよい。

## アーキテクチャ備考

- Site-wide settings（title, tagline, profile, SNS links, theme, pagination）は **単一の `SiteSetting` 行** に保存され、`SiteSetting.current` / `ApplicationController#current_site_setting` でアクセスする。設定フォームに admin 名前空間以外の認証はない。デフォルト値は `db/seeds.rb` で seeding される。
- Admin 認証は **カスタム実装（Devise 不使用）**（`Admin::SessionsController`、SHA256 + salt を使用した `AdminUser`）。セッションは `session[:admin_user_id]` に保存。オプションで signed cookie による永続ログインも可能。`Admin::BaseController#require_admin` が全管理画面ルートをガードする。
- `Post` は **enum** `status`（`draft`/`published`/`reviewing`）と `kind`（`article`/`experiment`）を使用。`Post.publicly_visible` は `published` かつ `published_at <= now` でフィルタ — 未来日付の投稿は公開画面では非表示だが、管理画面のプレビューでは表示される。
- 記事は `slug`（形式 `[a-z0-9-]+`）でスラッグ化。ルーティングは公開・管理両方の名前空間で `param: :slug` を使用。
- タグは管理フォームでカンマ区切り入力（`Post#tag_names=` / `=`）。パースはカンマで分割、トリム、重複除去、スラッグで `find_or_create_by!` する。
- 公開レイアウト（`layouts/application.html.erb`）とパーシャル（`shared/_header.html.erb`、`shared/_sidebar.html.erb`）が唯一のレイアウトファイル。Admin ビューは `app/views/admin/` 下に名前空間化され、同じレイアウトを再利用する（admin専用レイアウトはなし）。テーマ切り替えクラス（`theme-dark`）は `app/javascript/application.js` でトグルされる。

## デザイン・動作仕様

- デザイン要件は `docs/requirements.md` に定義。画面デザインは `docs/images/*.png` を参照。UI追加時は `docs/requirements.md` のセクション3–9および対応する画像と照合すること。
- デプロイアーキテクチャは `docs/deployment.md` に記載（Kamal + PostgreSQL accessory + Kamal proxy + Let's Encrypt）。インフラ変更時は `config/deploy.yml`、`config/postgres/init.sql`、`docs/deployment.md` を同期すること。

## デプロイ

- `kamal deploy` がデプロイエントリポイント。初回は `kamal setup`。
- サービス名は **`tech_notes`**（deploy.yml、accessory ホストエイリアス `tech_notes-db`、Active Storage ボリューム `tech_notes_storage` で使用）。内部 Docker ネットワークの DNS 名を決めるため、一貫して同じ名前を使うこと。
- シークレット（`RAILS_MASTER_KEY`, `POSTGRES_PASSWORD`, `ADMIN_PASSWORD`, オプションで `KAMAL_REGISTRY_PASSWORD`）は `.kamal/secrets` 経由で環境変数から注入 — 生の値をコミットしないこと。新規本番DBの初期化時は`ADMIN_EMAIL`と`ADMIN_PASSWORD`を必須とする。
- 本番環境は `RAILS_ENV=production`（`config/deploy.yml` の `env.clear` で設定）と、ホスト上に `config/master.key` が必要。
- レジストリは Docker Hub（`docker.io`）を使用し、イメージ名は`IMAGE`、レジストリユーザーは`REGISTRY_USERNAME`から取得する。`kamal setup` の前に `KAMAL_REGISTRY_PASSWORD`（Docker Hub アクセストークン）を環境変数に設定すること。
- `config/environments/production.rb` で `assume_ssl` / `force_ssl` / `host_authorization` が有効 — Kamal proxy（Traefik）が TLS を終端する。ステージング等で SSL を無効にする場合は、これらの設定も緩和しないとリクエストが失敗する。

## 注意点

- `/storage` ディレクトリは `.keep` を除き gitignore — 新規クローンでは `bin/rails db:prepare`（または `db:migrate` + `db:seed`）で SQLite ファイルを作成する必要がある。CI では `bin/rails db:test:prepare test` と `bin/rails db:test:prepare test:system` を実行。
- `config/master.key` は gitignore されており、**コミットしてはならない**。`bin/rails credentials` ワークフローでのみ再生成可能。紛失した場合は `credentials.yml.enc` を再暗号化する必要がある。
- `SiteSetting.current` の `site_url` と `profile_email` のデフォルトはサンプル値 — 本番環境の seed は `db/seeds.rb` で上書きすることを前提としている。本番ロジックで `SiteSetting.current` のデフォルトを信用せず、明示的な seeding を必須とすること。
- `MarkdownRenderer` の許可リスト（`ALLOWED_TAGS` / `ALLOWED_ATTRIBUTES`）は意図的に厳格に設定されている。新しい markdown 機能（例: 新しい HTML 要素）を追加する場合は `app/models/markdown_renderer.rb` の許可リストを更新しないと内容が黙って除去される — 合わせて `test/models/markdown_renderer_test.rb` にテストを追加すること。
- Markdown 中の画像挿入で URL に `remote-state-architecture` が含まれると、カスタムのインライン構成図がトリガーされる（`MarkdownRenderer#diagram_markup`）。この仕様を変更する場合は、レンダラーと対応する統合テストの両方を更新すること。
- 本番アプリをローカルで検証する際は、`DB_PORT`（およびその他の `POSTGRES_*` 環境変数）をローカルの PostgreSQL コンテナに向けること — 5432 ポートのデフォルトは本番アクセサリ用。
