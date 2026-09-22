# Hiroe Tech Notes MCP 機能仕様書

## 1. 概要

本ドキュメントは、Hiroe Tech Notes に MCP（Model Context Protocol）サーバーを追加し、AI クライアントから公開記事の検索・参照と下書きの作成・更新を行えるようにする機能の仕様を定義する。

**v1 は API キー（Bearer）認証のローカル／ヘッダー対応クライアント向け**とする。ChatGPT 本体への接続に必要な OAuth は v2 以降とする（Gemini向けOAuth認可サーバーは §18 のとおり実装済み）。

要件書本体は `docs/requirements.md`。本機能の詳細要件は本文書を正とする。

## 2. 背景・目的

| 項目 | 内容 |
|---|---|
| 背景 | ブログを自分の AI 用の知識倉庫として使いたい。AI クライアントから記事検索・下書き作成をチャット操作したい |
| 目的 | MCP サーバー経由で、公開記事の検索・参照と下書きの作成・更新を行えるようにする |
| 対象利用者 | サイト管理者（自分の AI クライアント） |
| v1 接続先 | MCP Inspector、Claude Desktop、Cursor など **HTTP + カスタムヘッダー（Bearer）を設定できるクライアント** |
| v1 非接続 | ChatGPT 本体（カスタム MCP 接続は OAuth が前提のため v2） |

## 3. スコープ

### 3.1 対象（やること）

- Rails アプリ内蔵の MCP エンドポイント（`/mcp`）の提供
- API キーによる認証（読み取り専用キー・書き込みキー）
- 管理画面からの API キー発行・一覧・失効
- MCP ツール: `search_posts` / `get_post` / `create_draft` / `update_draft`
- Bearer 認証で動くことを MCP Inspector / Claude Desktop 等で検証できること

### 3.2 非対象（やらないこと）

- 記事削除
- 公開・非公開の切り替え（publish / unpublish）
- OAuth / OpenID Connect（**ChatGPT 本体連携用。引き続き非対象**。Gemini向けOAuth認可サーバーは v2 として実装済み。詳細は §18）
- ChatGPT Plugins / カスタム MCP コネクタの接続
- レート制限（v1 では省略。将来検討）
- 複数管理者・多テナント対応
- WebMCP（ブラウザ内ツール公開）
- バックエンド MCP とは別のカスタム HTTP 公開 API の提供

## 4. 成功条件

- 管理画面で発行した API キーを **MCP Inspector または Claude Desktop 等**に設定し、記事検索・下書き作成がチャットで完結する
- 読み取りキーでは下書きを作成・更新できない
- 削除・公開をエージェントから実行できない（対応ツールが存在しない）
- API キーの平文がリポジトリ・ログに含まれない
- ChatGPT 本体での接続は v1 の受け入れ条件に含めない

## 5. アーキテクチャ

### 5.1 トランスポート

- **Rails アプリ内に MCP エンドポイントを置く**（Streamable HTTP transport）
- パス: `POST /mcp`（ルート名 `mcp`）
- Streamable HTTP の `GET`（SSE）/`DELETE`（セッション終了）も同パスで受付（`config/routes.rb`）。いずれも Bearer 認証必須（`McpController#authenticate_credential!`）
- 本番は既存の Kamal proxy（HTTPS）経由で到達可能なこと
- `/mcp` は `Admin::BaseController` のセッション認証を**使わない**（v1 は Bearer API キー認証のみ。v2 では OAuth トークンも受付。詳細は §18.4）

### 5.2 認証フロー

1. クライアントは `Authorization: Bearer <api_key>` を付与して `/mcp` へリクエスト
2. サーバーは API キーを検証し、スコープ（`read` / `write`）を解決
3. ツール実行時に、要求スコープが不足していれば実行前に拒否
4. 不正・失効キーは `401`、スコープ不足は `403`（MCP エラーとして応答）

v1 のフローは API キー認証のみ。v2 では OAuth トークンも受け付け、解決順序は API キー → Doorkeeper トークン（詳細は §18.4）。401 / 403 の形式は v1 と同一（§10）。

### 5.3 クライアント接続（v1）

| クライアント | v1 | キーの渡し方 |
|---|---|---|
| MCP Inspector | ○ | Connection に URL + HTTP headers（`Authorization: Bearer …`） |
| Claude Desktop | ○ | 設定 JSON の `headers` |
| Cursor ほかヘッダー対応 HTTP MCP | ○ | 各クライアントの headers 設定 |
| ChatGPT 本体（Plugins / カスタム MCP） | ×（v2） | URL のみ受付のため Bearer 貼り付け不可。OAuth が前提 |

v1 の動作確認は **MCP Inspector を正**とする。ChatGPT での疎通確認は行わない。

## 6. 認証・認可

### 6.1 API キー

| 項目 | 仕様 |
|---|---|
| 形式 | `tn_` + base58 32文字（全体35文字、`ApiKey.issue`）。一覧表示は先頭8文字（`key_prefix`） |
| 送信方法 | `Authorization: Bearer <api_key>` |
| 保存 | DB には**ハッシュのみ**保存（平文は発行時のみ表示） |
| 所有者 | 発行した管理者（`admin_user`）に紐付く。ツールの書き込みは**キー所有者の下書き**に対してのみ行う |
| 種別（スコープ） | `read`（読み取り専用） / `write`（読み取り + 下書き作成・更新） |
| 有効期限 | 任意（v1 では無期限可。発行画面で任意設定を将来検討） |
| 失効 | 管理画面から即時失効（失効後は即時拒否） |
| 最終使用日時 | リクエスト成功時に更新（表示のみ） |

### 6.2 スコープとツールの対応

| ツール | read | write |
|---|---|---|
| `search_posts` | ○ | ○ |
| `get_post` | ○ | ○ |
| `create_draft` | × | ○ |
| `update_draft` | × | ○ |

### 6.3 提供しない操作（明示的非スコープ）

- 削除、publish / unpublish、カテゴリー・タグの削除、サイト設定変更、管理ユーザー操作、翻訳・音声生成のトリガー

## 7. 管理画面: API キー管理

管理画面（認証済み）から API キーを発行・管理する。

### 7.1 画面配置

- 管理設定（`admin/settings`）に「MCP API キー」セクションを追加する（v1）
- 将来キー数が増える場合は専用ページへ切り出す

### 7.2 一覧表示

以下の列を表示する。

- 名前（ラベル）
- スコープ（読み取り専用 / 読み書き）
- キー先頭表示（例: `tn_ab12…` のみ。平文全体は表示しない）
- 作成日時
- 最終使用日時
- 状態（有効 / 失効）
- 操作: 失効（確認ダイアログ付き）

### 7.3 発行

- 「API キーを発行」操作で以下を入力・選択する。
  - 名前（必須、例: `Claude Desktop` / `MCP Inspector`）
  - スコープ（必須、`read` / `write` のいずれか）
- 発行したキーは**発行操作を行った管理者**に紐付ける（ログイン中の `current_admin_user`）
- 発行後、**平文キーを 1 回だけ画面に表示**する
- 表示にはコピー用ボタンを付ける
- 「閉じる」以降は平文を再表示できない旨を明示する

### 7.4 失効

- 有効なキーのみ失効できる
- 失効後も一覧には残る（監査用）。状態は「失効」
- 失効キーでの `/mcp` アクセスは即時拒否
- 失効は発行者本人のキーのみ（他管理者のキーは `current_admin_user.api_keys.find` で見つからず 404）

### 7.5 UI 要件

- 既存管理設定画面のデザイン方針（`docs/requirements.md` セクション 3、9）に従う
- テーブルは管理画面共通のスタイルを使用する
- ひらがな・漢字等の UI 文言は locale 経由（`ja` / `en`）
- 平文キー表示時の注意書き: 「このキーは一度しか表示されません。今すぐコピーしてください」

## 8. MCP ツール定義

ツールの `name` / `description` / エラーメッセージは **英語**で定義する（AI 連携が主目的であり、管理者 UI の文言ではない）。

### 8.1 `search_posts`

- **Description**: Search published blog posts by keyword. Returns post summaries (id, slug, title, published date, tags, excerpt).
- **入力**:
  - `query` (string, 必須): 検索キーワード（タイトル・本文・要約を対象）
  - `tags` (string[], 任意): タグ名で絞り込み（AND）
  - `limit` (number, 任意): 既定 10、最大 50
- **出力**: 公開済み記事の概要リスト
  - `id`, `slug`, `title`, `published_at`, `tags`, `excerpt`
- **条件**: `Post.publicly_visible` のみ対象
- 空クエリ時はツールエラー `"Provide a non-empty 'query' to search."` を返す

### 8.2 `get_post`

- **Description**: Get the full content of a published post by slug or id. Body is returned as Markdown.
- **入力**:
  - `slug` (string, どちらか一方必須)
  - `id` (number, どちらか一方必須)
- **出力**:
  - `id`, `slug`, `title`, `body`（Markdown のまま）, `excerpt`, `tags`, `published_at`
- **条件**: 公開済み記事のみ。下書き・レビュー中は取得不可（`not found` 相当で応答）
- `slug` と `id` の両方指定時はツールエラーで拒否（どちらか一方のみ）

### 8.3 `create_draft`

- **Description**: Create a new draft post. The post is always saved as a draft and is never published.
- **入力**:
  - `title` (string, 必須)
  - `body` (string, 必須): Markdown
  - `slug` (string, 任意): 省略時は title から生成（既存 `Post` の生成規則に従う）
  - `tags` (string[], 任意): タグ名の配列
- **出力**: `id`, `slug`, `title`, `status`（常に `draft`）
- **条件**:
  - `status` は**常に `draft`**。入力に status を持たせない
  - 要約（`excerpt`）は本文から自動生成する（`Post` の既存挙動に従う）
  - カテゴリーは既存デフォルト規則に従う
  - `admin_user` は**この API キーの所有者**（発行時の管理者）に紐付ける。キー所有者以外の `AdminUser.first` 等には紐付けない

### 8.4 `update_draft`

- **Description**: Update an existing draft post. Published posts cannot be updated with this tool.
- **入力**:
  - `id` または `slug`（どちらか一方必須）
  - 更新フィールド（いずれか 1 つ以上）: `title`, `body`, `slug`, `tags`
- **出力**: 更新後の `id`, `slug`, `title`, `status`
- **条件**:
  - 対象が `draft` のみ。`published` / `reviewing` は拒否
  - 対象が**この API キーの所有者の下書き**であること。所有者の下書き以外は not found 相当で拒否
  - 公開日時・ステータス変更は不可
  - `slug` の変更は `id` 指定時のみ可。`slug` で特定した場合は `slug` 変更不可（指定値は無視される）

### 8.5 提供しないツール

- 削除、公開、タグ一覧（`list_tags`）、サイト設定、その他管理操作

## 9. 入出力の共通仕様

- 記事本文は **Markdown のまま**返す（HTML 化しない。公開表示用レンダリングはクライアント側）
- 公開記事の取得・検索は `publicly_visible` と同等の条件のみ
- 下書きの作成・更新対象は、**認証に使用した API キーの所有者の下書き**に限る
- 検索・本文取得における既定 locale はアプリの既定 locale に従う（v1 では locale 指定入力を提供しない）

## 10. エラーハンドリング

| 状況 | HTTP | JSON-RPC code | 備考 |
|---|---|---|---|
| API キーなし・不正・失効 | `401` | `-32001` | `McpController#authenticate_credential!`（v2 では失効・期限切れの OAuth トークンも同形式で拒否） |
| スコープ不足（read キーで create 等） | `403` | `-32003` | `TOOL_SCOPES` による事前拒否 |
| 不正 JSON | `400` | `-32700` | SDK（StreamableHTTPTransport）由来 |
| 未知メソッド | `404` | `-32601` | SDK 由来 |
| ツール層エラー（対象なし・draft 限定違反・バリデーション・空クエリ等） | `200` | なし（`isError: true` の result） | HTTP は正常、ツール応答がエラー |
| slug 不正・タイトル空 | `200` | なし（`isError: true`） | バリデーション要旨（内部エラー全文は出さない） |
| ボディが空 | `200` | なし（`isError: true`） | |

- §14.4 の「不正 JSON・未知メソッド・スコープ不足・存在しない slug」は本表の 3・4・2・5 行目に対応する
- エラーは AI が自己修正できる簡潔な英語メッセージにする
- スタックトレース・SQL・API キー・セッション ID は応答・ログに含めない

## 11. データモデル（API キー）

新規テーブル `api_keys`（SQLite / PostgreSQL 両対応の標準 ActiveRecord マイグレーションで作成）。

| カラム | 型 | 備考 |
|---|---|---|
| `id` | bigint PK | |
| `admin_user_id` | bigint, not null, FK | 発行した管理者（キー所有者） |
| `name` | string, not null | 管理用ラベル |
| `key_digest` | string, not null, unique | 平文のハッシュ（例: SHA256） |
| `key_prefix` | string, not null | 一覧表示用（例: `tn_ab12`） |
| `scope` | string, not null | `read` / `write` |
| `revoked_at` | datetime, null | null=有効 |
| `last_used_at` | datetime, null | |
| `created_at` / `updated_at` | datetime | |

- `belongs_to :admin_user`（`AdminUser` 側 `has_many :api_keys, dependent: :restrict_with_exception` で採用済み。`app/models/admin_user.rb`）
- インデックス: `key_digest` unique、`admin_user_id`、`revoked_at`
- 平文キーは DB に保存しない

## 12. セキュリティ要件

- API キー平文は DB・ログ・エラーメッセージに出さない
- `/mcp` はセッションクッキーでは認証しない
- 本番は HTTPS のみ（既存 `force_ssl` を利用）
- 管理画面のキー管理は既存 `require_admin` ガードを使う
- CSRF: Bearer 認証の `/mcp` は通常 CSRF トークン対象外。セッション認証の管理画面は従来どおり CSRF 対象
- キー発行・失効操作は管理画面の通常の認証フローを通過したもののみ

## 13. 非機能要件

| 項目 | 要件 |
|---|---|
| i18n | 管理画面 UI 文言は `ja` / `en`。ツール description・エラーは英語固定 |
| パフォーマンス | 検索・取得は既存の公開記事クエリ方針に従う（N+1 を避ける） |
| 観測 | ツール名・成否・timestamp の簡易ログ（キー平文・本文全文はログに残さない） |
| テスト環境 | 外部 AI サービスには接続しない（MCP は自前エンドポイントのみ） |

## 14. テスト要件

### 14.1 認証・認可

- キーなし → 拒否
- 不正キー → 拒否
- 失効キー → 拒否
- `read` キーで `create_draft` / `update_draft` → 拒否
- `write` キーで読み取り・下書き作成・下書き更新 → 成功

### 14.2 ツール挙動

- `search_posts`: 公開記事のみヒット、下書き・レビュー中はヒットしない
- `get_post`: 公開記事は取得可、下書きは取得不可
- `create_draft`: `status` が常に `draft` になり、`admin_user` が**キー所有者**になる
- `update_draft`: draft のみ更新可、published / reviewing は拒否
- `update_draft`: **キー所有者以外の下書き**は更新できない
- ツール一覧に削除・公開系ツールが存在しないこと

### 14.3 管理画面

- 発行後、平文が一度表示される
- 一覧に平文全体は出ない
- 失効後は `/mcp` で使えない

### 14.4 エラー系

- 不正 JSON・未知メソッド・スコープ不足・存在しない slug

### 14.5 手動検証（v1）

- MCP Inspector で URL + `Authorization: Bearer` を設定し、4 ツールを呼び出す
- read キーで `create_draft` が拒否されることを確認する
- Claude Desktop（任意）で同様に疎通する
- ChatGPT 本体での接続確認は **v1 の検証対象外**

## 15. 実装上の指針（設計メモ）

- ツール実行ロジックは `Post` / サービスクラスを再利用し、MCP コントローラには薄く載せる
- MCP プロトコルのパース／応答は公式 SDK（`mcp` gem）の Rails controller パターン + stateless モードを採用（`McpController`、`Gemfile`）
- 管理画面の API キー発行 UI を伴うため、`docs/requirements.md` の管理設定要件への導線を本ドキュメントに置き換える
- マイグレーションは SQLite（dev/test）と PostgreSQL（本番）の両方で動作すること
- v1 では ChatGPT 向け OAuth・プラグイン申請・コネクタ UI は実装しない（Gemini向けOAuth認可サーバーは §18 で v2 として実装。ChatGPT 本体連携は引き続き非対象）

## 16. 受け入れ条件

- [ ] `/mcp` に API キーで到達でき、ツール一覧が取得できる
- [ ] MCP Inspector（または同等のヘッダー対応クライアント）から 4 ツールを呼び出せる
- [ ] 管理画面から read / write キーを発行・失効できる
- [ ] 認証・スコープ・公開/下書きの境界がテストで担保されている
- [ ] 削除・公開ツールが存在しない
- [ ] `bin/rails test` がパスする
- [ ] API キー平文が git 管理下のファイルに含まれない
- [ ] ChatGPT 本体接続は v1 の完了条件に含めない

## 17. 将来拡張候補（v2 以降）

- ~~OAuth による ChatGPT 本体連携~~ — v2 として Gemini向けOAuth認可サーバーを実装済み（§18）。ChatGPT 本体連携は引き続き非対象
- レート制限
- 公開操作（人間承認付き）
- locale 指定での検索・取得
- MCP 以外向けの読み取り専用 HTTP API
- Service Worker / WebMCP との連携（非対象のまま維持）

## 18. v2: OAuth認可サーバー（Gemini連携）

### 18.1 背景・目的

- Gemini のカスタムアプリ登録のように、接続時に OAuth クライアント情報（クライアントID・シークレット・認可／トークンエンドポイント）を必須とするクライアントには、v1 の Bearer API キー直貼りでは接続できない。
- 本アプリ自身を OAuth 認可サーバーとし、Gemini を事前登録クライアントとして受け入れることで、Gemini から MCP ツール（§8）を利用できるようにする。

### 18.2 アーキテクチャ

- 認可サーバーに Doorkeeper 5.9.7（`Gemfile` の `gem "doorkeeper", "~> 5.9"`、`Gemfile.lock`）を使用する。
- 認可コードフロー + PKCE（S256）+ リフレッシュトークン（`config/initializers/doorkeeper.rb`）。
- DCR（Dynamic Client Registration）なし。クライアントは事前登録方式（§19 の手順で `Doorkeeper::Application` を作成）。接続相手が管理者自身の Gemini アプリに限定され、動的登録の必要がなく攻撃面を増やさないため。
- アプリケーション管理 UI は非公開（`config/routes.rb` の `use_doorkeeper` で `skip_controllers :applications, :authorized_applications`）。
- 認可サーバーメタデータは自作の `OauthMetadataController`（`app/controllers/oauth_metadata_controller.rb`）で提供する。

### 18.3 エンドポイント

| エンドポイント | 用途 |
|---|---|
| `GET/POST /oauth/authorize` | 認可リクエスト・同意（Doorkeeper 標準） |
| `POST /oauth/token` | トークン交換（`authorization_code`）・更新（`refresh_token`） |
| `POST /oauth/revoke` | トークン失効 |
| `GET /.well-known/oauth-authorization-server` | 認可サーバーメタデータ（基底形のみ。`issuer` は origin 直下。path-inserted 形は提供しない） |

Doorkeeper の `grant_flows` は `authorization_code` のみ（`config/initializers/doorkeeper.rb`）。implicit / password / client_credentials は無効。リフレッシュは `use_refresh_token` で有効化している。

メタデータの応答項目（`app/controllers/oauth_metadata_controller.rb#show`）: `issuer`、`authorization_endpoint`、`token_endpoint`、`revocation_endpoint`、`response_types_supported`（`code`）、`grant_types_supported`（`authorization_code` / `refresh_token`）、`code_challenge_methods_supported`（`S256`）、`scopes_supported`（`read` / `write`）、`token_endpoint_auth_methods_supported`（`client_secret_basic` / `client_secret_post` / `none`：publicクライアント用）。

### 18.4 スコープ対応

- OAuth スコープ `read` / `write`（`config/initializers/doorkeeper.rb` の `optional_scopes :read, :write`＋`default_scopes :read`。未指定時は `read` が付与・表示される）がそのまま MCP スコープ（§6.2）に対応する。
- `/mcp` の認証解決順序（`app/controllers/mcp_controller.rb#authenticate_credential!`）:
  1. API キー（`ApiKey.find_active_by_token`）
  2. Doorkeeper トークン（`Doorkeeper::AccessToken.by_token` + `accessible?`。所有者は `resource_owner_id` の `AdminUser`、スコープは `includes_scope?("write")` で `write` / `read` を判定）
- `server_context` は `{ owner, scope }` 形（ツール層は `api_key` ではなく `owner` と `scope` で判定。`app/mcp/create_draft_tool.rb`、`app/mcp/update_draft_tool.rb`）。
- 401 / 403 の形式は v1 と同一（§10）。OAuth トークンの失効・期限切れは 401（`-32001`）、read スコープでの書き込みツール呼び出しは 403（`-32003`）。

### 18.5 トークン有効期限・失効の扱い

- アクセストークン有効期限は 2 時間（`config/initializers/doorkeeper.rb` の `access_token_expires_in 2.hours`）。
- リフレッシュトークン有効（`use_refresh_token`）。更新時は `grant_type=refresh_token` で `/oauth/token` へリクエストする。
- 失効は `POST /oauth/revoke` で行う。失効済み・期限切れトークンでの `/mcp` アクセスは 401（`-32001`）で即時拒否される。
- アクセス・リフレッシュトークンは DB にハッシュ保存される（`hash_token_secrets`）。平文での直接参照はできず、解決は `Doorkeeper::AccessToken.by_token` 経由で行う。

### 18.6 同意画面の仕様

- 自作の最小ビュー（`app/views/doorkeeper/authorizations/new.html.erb`）。表示項目:
  - タイトル（`oauth.authorize.title`）
  - `「<クライアント名> があなたのアカウントへのアクセスを求めています」`（`oauth.authorize.prompt`）
  - 操作一覧（`oauth.authorize.able_to` + 要求スコープごとの説明）
  - 許可ボタン（`oauth.authorize.authorize`）/ 拒否ボタン（`oauth.authorize.deny`）
- ja / en 対応（`config/locales/ja.yml`・`config/locales/en.yml` の `oauth.authorize.*`）。`read` = `記事の閲覧` / `Read articles`、`write` = `記事の作成・更新` / `Create and update articles`。
- 拒否時はクライアントへ `access_denied` でリダイレクトし、認可コード・トークンは何も発行しない。

### 18.7 PKCE受容判断

- `force_pkce` + S256 のみ（`config/initializers/doorkeeper.rb` の `force_pkce`、`pkce_code_challenge_methods %w[S256]`）。なお Doorkeeper 標準の `force_pkce` は非 confidential クライアントに適用される。
- Gemini 想定の confidential クライアントは、トークンエンドポイントでの secret 認証（`client_secret_basic` / `client_secret_post`）に加え、MCP 仕様に沿ってクライアント側で PKCE（`code_challenge` 送信）を実施することを前提として受け入れる。

### 18.8 未ログイン時の認可URL復帰

- 未ログインで `/oauth/authorize` にアクセスした場合、管理者ログインへ誘導する（`config/initializers/doorkeeper.rb` の `resource_owner_authenticator` が `session[:return_to] = request.fullpath` を保存して `admin_login_path` へリダイレクト）。
- ログイン成功後は元の認可 URL へ復帰する（`app/controllers/admin/sessions_controller.rb`）。復帰先は内部パスのみ（`/` 始まりかつ `//` 除外）。それ以外は管理記事一覧（`admin_posts_path`）へ遷移する。

### 18.9 テスト要件

- 自動テストは `test/integration/oauth_test.rb` で担保する:
  - 認可フロー: PKCE ありの正常系（認可コード → アクセス + リフレッシュトークン発行、有効期限 2 時間）、PKCE なしの拒否、verifier 不一致の拒否、redirect_uri 不一致の拒否
  - 同意拒否（`access_denied` でリダイレクトし何も発行しない）、未ログイン誘導（管理者ログインへリダイレクトし `session[:return_to]` に認可パスを保存）
  - トークン: リフレッシュによる更新、`/oauth/revoke` による失効
  - メタデータ（基底形）の内容
  - スコープ: OAuth write トークンでのツール一覧・下書き作成の成功、read トークンでの書き込み 403（`-32003`）
  - 回帰: 失効トークンの 401（`-32001`）、期限切れトークンの 401（`-32001`）
- v1 回帰は `test/integration/mcp_test.rb` で担保する（`server_context` は `{ owner, scope }` 形に更新済み）。
- 手動検証: Gemini のカスタムアプリ登録（§19）による実接続確認。外部 AI サービスへの自動接続テストは行わない。

## 19. 本番runbook: Gemini用クライアント登録

本番 Rails コンソールで実行する。実値（ドメイン・クライアントID・secret）は本書に記載しない。

### 19.1 新規登録

Gemini の設定画面に表示されるリダイレクト URI の値を転記して実行する。

```ruby
app = Doorkeeper::Application.create!(
  name: "Gemini",
  redirect_uri: "<Gemini設定画面の値を転記>",
  scopes: "read write",
  confidential: true
)
app.uid    # → Gemini の「OAuth クライアントID」欄へ転記
app.secret # → Gemini のシークレット欄へ転記
```

- 作成コマンドの戻り値（`inspect`）の `secret` は `[FILTERED]` 表示になるため、`app.secret` リーダーで取得すること
- ハッシュ化無効のため `app.secret` は後から再取得できるが、発行直後に Gemini 側へ登録し、使い捨てと同様に慎重に扱うこと
- シェル履歴・ログに secret を残さないこと（履歴への書き込み抑止、登録後の履歴・クリップボードのクリア）。

### 19.2 redirect_uri 変更時の更新

```ruby
app = Doorkeeper::Application.find_by(name: "Gemini")
app.update!(redirect_uri: "<新しい値を転記>")
```

変更後は Gemini 側の登録値と一致していることを確認し、認可フロー（§18.9 の手動検証）で疎通を再確認する。

### 19.3 クライアント失効

```ruby
app = Doorkeeper::Application.find_by(name: "Gemini")
app.destroy!
```

`Doorkeeper::Application` の削除時は関連する認可コード・トークンがまとめて削除される（Doorkeeper 5.9.7 の `dependent: :delete_all`）。削除後は Gemini 側の登録も無効化すること。

### 19.4 トークン失効

単発の失効は `/oauth/revoke` へ POST する。コンソールで直接失効させる場合は以下を実行する。

```ruby
Doorkeeper::AccessToken.by_token("<失効対象トークン>").revoke
```

失効後は該当トークンでの `/mcp` アクセスが 401（`-32001`）になることを確認する。
