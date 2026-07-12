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

## リンター / セキュリティスキャン

- スタイルは Rails Omakase 準拠: `bin/rubocop` で `rubocop-rails-omakase` 設定を実行。CI では `bin/rubocop -f github`。
- `bin/brakeman --no-pager` と `bin/bundler-audit` を CI で実行（追加引数なし）。
- JS 依存関係は `bin/importmap audit` で監査。

## Dependabot PR の処理

- Dependabot が起票した PR の処理は `.agents/skills/dependabot-pr/SKILL.md` の手順に従うこと。
- 本リポジトリに Dependabot 設定ファイル（`.github/dependabot.yml`）がない場合は、同スキルの提案内容を参照してユーザーと相談すること。

## コミット前のセキュリティチェック

- `git commit` を実行する**前に必ず** `.agents/skills/security-check/SKILL.md` の手順に従い、リポジトリ全体の機密情報スキャンを実行すること。
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

- `/storage` ディレクトリは `.keep` を除き gitignore — 新規クローンでは `bin/rails db:prepare`（または `db:migrate` + `db:seed`）で SQLite ファイルを作成する必要がある。CI では `bin/rails db:test:prepare test` を実行。
- `config/master.key` は gitignore されており、**コミットしてはならない**。`bin/rails credentials` ワークフローでのみ再生成可能。紛失した場合は `credentials.yml.enc` を再暗号化する必要がある。
- `SiteSetting.current` の `site_url` と `profile_email` のデフォルトはサンプル値 — 本番環境の seed は `db/seeds.rb` で上書きすることを前提としている。本番ロジックで `SiteSetting.current` のデフォルトを信用せず、明示的な seeding を必須とすること。
- `MarkdownRenderer` の許可リスト（`ALLOWED_TAGS` / `ALLOWED_ATTRIBUTES`）は意図的に厳格に設定されている。新しい markdown 機能（例: 新しい HTML 要素）を追加する場合は `app/models/markdown_renderer.rb` の許可リストを更新しないと内容が黙って除去される — 合わせて `test/models/markdown_renderer_test.rb` にテストを追加すること。
- Markdown 中の画像挿入で URL に `remote-state-architecture` が含まれると、カスタムのインライン構成図がトリガーされる（`MarkdownRenderer#diagram_markup`）。この仕様を変更する場合は、レンダラーと対応する統合テストの両方を更新すること。
- 本番アプリをローカルで検証する際は、`DB_PORT`（およびその他の `POSTGRES_*` 環境変数）をローカルの PostgreSQL コンテナに向けること — 5432 ポートのデフォルトは本番アクセサリ用。
