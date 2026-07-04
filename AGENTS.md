# AGENTS.md

This file guides AI agents (and humans) working in this repo. It captures non-obvious conventions and workflows that would otherwise require reading multiple files to infer.

## Communication

- すべてのユーザー向けメッセージ（説明・質問・要約・コミットメッセージ案を含む）は**日本語**で記述すること。
- コミットメッセージは**日本語**で記述すること。

## Stack

- Rails 8.1 on Ruby 3.4.9 (`rbenv`, version pinned in `.ruby-version`)
- Bundle path is `vendor/bundle` (not the global location) — set in `.bundle/config`. Any `bundle install` keeps gems local.
- Frontend: importmap + Stimulus, no Node.js toolchain. JS lives in `app/javascript/`; pinning in `config/importmap.rb`.
- Markdown rendered server-side via `MarkdownRenderer` (`app/models/markdown_renderer.rb`) using `commonmarker` + a Nokogiri-based sanitization pass. Public article rendering and admin live-preview both go through this single renderer. Any new markdown touchpoint must use `PostsHelper#render_markdown` / `#extract_headings` — do not render markdown from controllers/views directly.

## Database (split adapters — important)

- **Development and test use SQLite** (`storage/*.sqlite3`).
- **Production uses PostgreSQL** via Kamal accessory, with 4 logical DBs on the same cluster: `tech_notes_production{,_cache,_queue,_cable}`. Initialisation SQL is `config/postgres/init.sql`.
- `config/database.yml` reads env vars (`DB_HOST`, `DB_PORT`, `POSTGRES_USER`, `POSTGRES_PASSWORD`, plus `POSTGRES_DB{,_CACHE,_QUEUE,_CABLE}`) for production.
- **Never add migrations that use SQLite-specific or PostgreSQL-specific features without verifying they work on both adapters** — dev/test still run on SQLite while production runs on PostgreSQL.
- Solid Cache / Queue / Cable are wired to the `cache` / `queue` / `cable` roles in production (`config/{cache,queue,cable}.yml`).
- `bin/rails db:prepare` is the canonical prepare command — invoked by `bin/docker-entrypoint` on production boot. Use it locally too.

## Testing

- Single integration suite covers the whole app: `test/integration/blog_flow_test.rb` (most assertions live here). Model tests are tiny and focused.
- Tests run on **SQLite in `RAILS_ENV=test`** — no external services required.
- Run all: `bin/rails test`
- Run system tests: `bin/rails test:system`
- Run a single file: `bin/rails test test/integration/blog_flow_test.rb`
- Run a single test by name: `bin/rails test test/integration/blog_flow_test.rb -n test_admin_can_sign_in_and_view_management_pages`
- System tests live under `test/system/` and cover browser-driven JavaScript behavior. They require Chromium/Chrome and Chromedriver; in sandboxed environments they may need to run outside the sandbox because Capybara/Selenium use local socket communication.
- `parallelize(workers: :number_of_processors)` is enabled — failures may interleave; rerun with `--seed` from the failure output for stable ordering.
- Fixtures are minimal (`test/fixtures/files/` only has `not-image.txt` for Active Storage validation tests). Tests build records in `setup` instead.
- Admin password hashing is custom (`AdminUser.digest_password` with a per-user salt + secret_key_base). When creating an `AdminUser` in tests, pass `password_salt:` and `password_digest: AdminUser.digest_password(...)` — the `password=` setter regenerates the salt and is awkward to use in test setup.

## Feature implementation workflow

- 機能追加は、要件整理、設計、実装、テスト実装、テスト実行、Rubocopなどのリンター実行の順で進める。
- UIや画面挙動を追加・変更する場合は、実装前に `docs/requirements.md` の該当セクションへ要件を追記または更新する。

## Lint / security scans

- Style follows Rails Omakase: `bin/rubocop` runs `rubocop-rails-omakase` config. CI runs `bin/rubocop -f github`.
- `bin/brakeman --no-pager` and `bin/bundler-audit` run in CI (no extra args expected).
- JS deps audited via `bin/importmap audit`.

## Architecture notes

- Site-wide settings (title, tagline, profile, SNS links, theme, pagination) live in a **single `SiteSetting` row** accessed via `SiteSetting.current` / `ApplicationController#current_site_setting`. There is no admin auth on the settings form beyond the admin namespace; defaults are seeded in `db/seeds.rb`.
- Admin auth is **custom, not Devise** (`Admin::SessionsController`, `AdminUser` with SHA256 + salt). Session stored in `session[:admin_user_id]`; optional persistent cookie via signed `admin_user_id`. `Admin::BaseController#require_admin` gates all admin routes.
- `Post` uses **enum** `status` (`draft`/`published`/`reviewing`) and `kind` (`article`/`experiment`). `Post.publicly_visible` filters `published` AND `published_at <= now` — future-dated posts are hidden publicly but visible in admin preview.
- Articles slugged by `slug` (format `[a-z0-9-]+`); routes use `param: :slug` in both public and admin namespaces.
- Tags are comma-separated in the admin form (`Post#tag_names=` / `=`); parsing splits on comma, strips, de-duplicates, and `find_or_create_by!` by slug.
- The public layout (`layouts/application.html.erb`) and partials (`shared/_header.html.erb`, `shared/_sidebar.html.erb`) are the only layout files. Admin views are namespaced under `app/views/admin/` and reuse the same layout (no admin-specific layout). Theme switching classes (`theme-dark`) are toggled by `app/javascript/application.js`.

## Design / behaviour reference

- Visual and functional requirements are defined in `docs/requirements.md`. Screen designs in `docs/images/*.png` are the reference. When adding UI, cross-check against `docs/requirements.md` sections 3–9 and the corresponding image.
- Deployment architecture is documented in `docs/deployment.md` (Kamal + PostgreSQL accessory + Kamal proxy + Let's Encrypt). Keep `config/deploy.yml`, `config/postgres/init.sql`, and `docs/deployment.md` in sync when changing infra.

## Deployment

- `kamal deploy` is the deploy entrypoint. `kamal setup` for first-time bootstrap.
- Service name is **`tech_notes`** (used in deploy.yml, accessory host alias `tech_notes-db`, and the Active Storage volume `tech_notes_storage`). Keep this consistent — it determines the internal Docker network DNS name.
- Secrets (`RAILS_MASTER_KEY`, `POSTGRES_PASSWORD`, optional `KAMAL_REGISTRY_PASSWORD`) are wired through `.kamal/secrets` using environment variables — never commit raw secrets.
- Production env requires `RAILS_ENV=production` (set in `config/deploy.yml` `env.clear`) and `config/master.key` present on the host.
- Registry is Docker Hub (`docker.io`) with image `hiroeorz/tech_notes`. Set `KAMAL_REGISTRY_PASSWORD` (Docker Hub access token) in the environment before `kamal setup`.
- `config/environments/production.rb` enables `assume_ssl` / `force_ssl` / `host_authorization` — Kamal proxy (Traefik) terminates TLS. If SSL is disabled for staging, you must also relax these settings or requests will fail.

## Gotchas

- The `/storage` directory is gitignored except `.keep` — fresh clones need `bin/rails db:prepare` (or `db:migrate` + `db:seed`) to create the SQLite files. CI runs `bin/rails db:test:prepare test`.
- `config/master.key` is gitignored and **must not** be committed. It is regenerated only via `bin/rails credentials` workflows; if lost, you must re-encrypt `credentials.yml.enc`.
- `site_url` and `profile_email` defaults in `SiteSetting.current` are sample values — production seeds expect `db/seeds.rb` to overwrite them. Don't trust `SiteSetting.current` defaults for production logic; require explicit seeding.
- The `MarkdownRenderer` allow-list (`ALLOWED_TAGS` / `ALLOWED_ATTRIBUTES`) is intentionally strict. Adding a new markdown feature (e.g. a new HTML element) requires updating the allow-list in `app/models/markdown_renderer.rb` or the content will be silently stripped — and add a test in `test/models/markdown_renderer_test.rb`.
- Image insertion in markdown with `remote-state-architecture` in the URL triggers a custom inline architecture diagram (`MarkdownRenderer#diagram_markup`). Changing this convention requires updating both the renderer and the corresponding integration test.
- When running the production app locally for verification, set `DB_PORT` (and other `POSTGRES_*` env vars) to point at a local PostgreSQL container — port 5432 defaults are for the production accessory.
