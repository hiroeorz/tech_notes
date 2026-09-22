# Hiroe Tech Notes MCP 機能仕様書

## 1. 概要

本ドキュメントは、Hiroe Tech Notes に MCP（Model Context Protocol）サーバーを追加し、AI クライアントから公開記事の検索・参照と下書きの作成・更新を行えるようにする機能の仕様を定義する。

**v1 は API キー（Bearer）認証のローカル／ヘッダー対応クライアント向け**とする。ChatGPT 本体への接続に必要な OAuth は v2 以降とする。

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
- OAuth / OpenID Connect（**ChatGPT 本体連携用。v2 以降**）
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
- 本番は既存の Kamal proxy（HTTPS）経由で到達可能なこと
- `/mcp` は `Admin::BaseController` のセッション認証を**使わない**（Bearer API キー認証のみ）

### 5.2 認証フロー

1. クライアントは `Authorization: Bearer <api_key>` を付与して `/mcp` へリクエスト
2. サーバーは API キーを検証し、スコープ（`read` / `write`）を解決
3. ツール実行時に、要求スコープが不足していれば実行前に拒否
4. 不正・失効キーは `401`、スコープ不足は `403`（MCP エラーとして応答）

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
| 形式 | 例: `tn_<ランダム文字列>`（推測困難な 32 文字以上） |
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

### 8.2 `get_post`

- **Description**: Get the full content of a published post by slug or id. Body is returned as Markdown.
- **入力**:
  - `slug` (string, どちらか一方必須)
  - `id` (number, どちらか一方必須)
- **出力**:
  - `id`, `slug`, `title`, `body`（Markdown のまま）, `excerpt`, `tags`, `published_at`
- **条件**: 公開済み記事のみ。下書き・レビュー中は取得不可（`not found` 相当で応答）

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

### 8.5 提供しないツール

- 削除、公開、タグ一覧（`list_tags`）、サイト設定、その他管理操作

## 9. 入出力の共通仕様

- 記事本文は **Markdown のまま**返す（HTML 化しない。公開表示用レンダリングはクライアント側）
- 公開記事の取得・検索は `publicly_visible` と同等の条件のみ
- 下書きの作成・更新対象は、**認証に使用した API キーの所有者の下書き**に限る
- 検索・本文取得における既定 locale はアプリの既定 locale に従う（v1 では locale 指定入力を提供しない）

## 10. エラーハンドリング

| 状況 | 挙動 |
|---|---|
| API キーなし・不正 | `401` / MCP 認証エラー |
| 失効キー | `401` |
| スコープ不足（read キーで create 等） | `403` / MCP エラー |
| 対象下書きが存在しない | ツールエラー: 記事が見つからない旨の英語メッセージ |
| published / reviewing を更新 | ツールエラー: 下書きのみ更新可能の旨 |
| slug 不正・タイトル空 | ツールエラー: バリデーション要旨（内部エラー全文は出さない） |
| ボディが空 | ツールエラー |

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

- `belongs_to :admin_user`（`dependent: :restrict_with_exception` を検討。AdminUser と同方針）
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
- MCP プロトコルのパース／応答は Rails に載せやすい最小実装を検討する（ gem 追加時は `AGENTS.md` のライブラリ選定基準に従う）
- 管理画面の API キー発行 UI を伴うため、`docs/requirements.md` の管理設定要件への導線を本ドキュメントに置き換える
- マイグレーションは SQLite（dev/test）と PostgreSQL（本番）の両方で動作すること
- v1 では ChatGPT 向け OAuth・プラグイン申請・コネクタ UI は実装しない

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

- **OAuth による ChatGPT 本体連携**（カスタム MCP / プラグイン接続の前提）
- レート制限
- 公開操作（人間承認付き）
- locale 指定での検索・取得
- MCP 以外向けの読み取り専用 HTTP API
- Service Worker / WebMCP との連携（非対象のまま維持）
