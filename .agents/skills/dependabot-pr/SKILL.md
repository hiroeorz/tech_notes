---
name: dependabot-pr
description: GitHub Dependabot が起票したプルリクエストの調査・検証・マージまでを一貫して行う。古い PR から順に処理し、ユーザーの判断を仰ぎながら進める。
---

Dependabot が起票した PR を処理するよう指示された場合、または定期的な依存関係更新の一環として、このスキルの手順に従うこと。

本スキルが実行されたら、定義済みのサブエージェントを積極的に使うこと。
特に
* 設計: solution_architect
* コードレビュー: code_reviewer
* データベースレビュー: database_reviewer
* ドキュメント更新: documentation_manager
* Railsコーディング: rails_implementer
* フロントエンドコーディング: frontend_implementer
* セキュリティレビュー: security_auditor
* テスト: test_engineer
* git, github 操作: repository_operator
* 原因調査: bug_investigator

の使用を推奨する。
他のエージェントについても必要に応じて起動して作業を進めること。
各サブエージェントが使用するLLMモデルについては、各サブエージェントで定義されているモデルを使用すること。

ユーザー向け文言を追加・変更する場合は `.agents/skills/translation/SKILL.md`（必要に応じて `.agents/skills/internationalization/SKILL.md`）に従うこと。

**各フェーズにおいて、変更内容や影響範囲が不明瞭な場合は、その時点でユーザーに確認し、明確にしてから次に進むこと。**

## 並列実行ポリシー

独立して実行できるタスクは、サブエージェントや並列ツール呼び出しを使って**同時に実行する**こと。直列に並べるだけにしない。

- リサーチ（CHANGELOG確認・使用箇所検索・影響調査）は相互に独立しているため、**同一メッセージで複数のツール呼び出し**を行って並列実行する。
- 読み取り専用のサブエージェント（code_reviewer、database_reviewer、security_auditor、bug_investigator、test_engineer の調査など）は互いに依存がなければ、**同一メッセージで複数起動**して並列化する。
- `Gemfile.lock` のコンフリクトを避けるため、PRのマージ自体は古い順に直列で行う。`bin/rails test` と `bin/rails test:system` はテストDB・ブラウザ資源を共有するため並列にせず直列化する。
- 静的解析（`bundle exec srb tc`、`bin/rubocop`、`bin/brakeman --no-pager`、`bin/bundler-audit`、`bin/importmap audit`）は相互に独立しているため、**同一メッセージで複数の bash ツール呼び出し**を行って並列実行してよい。
- Dependabotブランチへの直接修正は行わないのが基本である。アプリケーションコードの修正が必要になった場合は通常のトピックブランチで対応し（本スキルの範囲外）、読み取り専用レビューと編集が重なる場合は変更ファイルが重複しないことを確認する。
- サブエージェントには対象PR番号・ファイル一覧・レビューまたは調査の観点をプロンプトで明示する。シェルを持たず `git diff` を実行できないエージェントがいるため、自分で差分を取得できる前提にしない。

## 処理フロー概要

以下の各フェーズを順に実行する。**各フェーズの成果物がまとまった時点でユーザーに確認を求め、了承を得てから次のフェーズに進むこと。**

```
全オープン Dependabot PR の把握
  ↓
PR ごとに: 変更内容調査 → 影響評価
  ↓
ユーザーにマージ判断を仰ぐ
  ↓
マージ判断の場合: ローカル検証（bundle install → test → rubocop → セキュリティ）
  ↓
PR マージ・クローズ
  ↓
未処理の PR があれば次の PR へ（古い順にループ）
  ↓
全 PR 処理後の報告（全体テスト + gem RBI 同期 + CI 確認）
```

---

## フェーズ0: 前提条件の確認

以下のツールが利用可能であることを確認する。不足があればユーザーに知らせて対応を仰ぐ。

- `gh` CLI がインストールされ、GitHub 認証が済んでいること
- `git` が正しく設定され、リモートリポジトリにアクセスできること
- ローカル環境で `bin/rails test` が実行可能な状態であること（bundle 済み、DB 準備済み）
- `bin/bundler-audit` が Gemfile.lock の読み取りに成功すること

```bash
gh auth status 2>&1 || echo "gh CLI の認証が必要です"
git remote -v
bin/rails test --version 2>&1 || echo "テスト環境が準備できていません"
```

---

## フェーズ1: 全オープン Dependabot PR の把握

### 1.1 PR 一覧の取得

```bash
gh pr list --author "app/dependabot" --state open --json number,title,createdAt,headRefName,baseRefName,url --jq 'sort_by(.createdAt)'
```

このリポジトリの `.github/dependabot.yml` では bundler の更新を週次（金曜17:00 JST、`Asia/Tokyo`）で確認する。設定が変更されている場合は、実ファイルの内容を正として対象エコシステムと更新間隔を報告する。

patch 更新は `.github/workflows/auto-merge-patches.yml` により自動承認・自動マージ（squash）される。処理開始時点で既にマージ済み・クローズ済みの patch PR があれば対象外とし、残りの PR だけを報告する。

### 1.2 全体像の報告

取得した PR 一覧をユーザーに以下の形式で報告する。**報告は日本語で行う**（中国語など他言語を混入させない）:

```
📋 Dependabot PR 一覧（全 N 件、古い順）:
1. #<番号> <タイトル>（<作成日>）
2. #<番号> <タイトル>（<作成日>）
...
```

合わせて、処理予定の順序（古い順）とおおまかな工数感を伝え、続行の了承を得る。

成果物: Dependabot PR 一覧（ユーザー確認済み）

---

## フェーズ2: 個別 PR の調査（PR ごとに繰り返す）

以下の手順を古い PR から順に1件ずつ実行する。独立した調査（リリースノート確認・使用箇所検索・影響調査）は並列実行ポリシーに従い並列化してよい。

### 2.1 PR 詳細の取得

```bash
gh pr view <PR番号> --json title,body,files,additions,deletions,reviews,state,createdAt,headRefName,baseRefName
```

### 2.2 変更内容の把握

以下の情報を整理する:

- **更新対象**: Gem 名 / ライブラリ名（`Gemfile` / `Gemfile.lock` の差分から特定）
- **バージョン変化**: 旧バージョン → 新バージョン（major / minor / patch の種別）
- **CHANGELOG / Release Notes**: 以下いずれかの方法で確認する
  - GitHub Releases ページを WebFetch で取得
  - GitHub リポジトリの CHANGELOG.md / NEWS.md を確認
  - RubyGems ページの changelog リンクを確認
- **Breaking Changes**: メジャーバージョンアップの場合は特に注意深く確認する
- **脆弱性修正**: セキュリティ関連の更新かどうか（Dependabot の PR タイトルに `[Security]` と付く場合がある）
- **patch 自動マージ対象か**: `version-update:semver-patch` であれば自動マージされるため、手動マージ判断は原則不要（PRブランチではCIが実行されないため、残っている場合は個別判断する）。patch の自動マージは PR の CI 結果を待たずに main へ入る（main の CI が唯一の自動検証。この無検証マージは受容済みのリスクであり、main の CI が失敗した場合は通常フローで修正する）

### 2.3 依存関係の影響調査

更新対象の Gem が、以下の観点でプロジェクトにどのように影響するか調査する:

- `Gemfile` で直接依存しているか、間接依存か
- アプリケーションコード内で該当 Gem のどの機能を使用しているか
- 既存のテストでカバーされている利用箇所の範囲
- マイグレーションや設定変更が必要かどうか

```bash
# 該当 Gem の使用箇所をコードベースから検索
rg "<gem-name>" app/ --type-add 'ruby:*.rb' --type ruby
rg "<gem-name>" config/ --type-add 'ruby:*.rb' --type ruby
# Module/Class 名で検索（Gem によっては名前空間が異なる）
rg "<ModuleName>" app/ --type ruby
```

### 2.4 影響評価レポート

以下の形式でユーザーに報告する（各 PR ごと）。**報告は日本語で行う**（中国語など他言語を混入させない）:

```
## PR #<番号>: <元のPRタイトル>

### 変更概要
- **更新**: <Gem名> <旧バージョン> → <新バージョン>
- **種別**: major / minor / patch / security
- **作成日**: YYYY-MM-DD

### リリースノート/CHANGELOG 抜粋
<主要な変更点、特に breaking changes があれば記載>

### 影響範囲
- コード内での使用箇所: <ファイルパス:行 など>
- マイグレーション/設定変更: 必要 / 不要
- テストカバレッジ: 十分 / 不足（補足）

### リスク評価
- 🟢 低リスク: patch / minor で互換性に問題がない
- 🟡 中リスク: 注意深い確認が必要（minor でも影響大 / API変更あり）
- 🔴 高リスク: major で breaking changes あり
- 🟣 セキュリティ: 脆弱性修正を含む

### 推奨アクション
- ✅ マージ推奨（理由）
- ⚠️ 条件付きマージ（確認事項）
- ❌ マージ非推奨（理由）
```

**パッチ / マイナーでコード内の使用箇所が単純かつ互換性に問題ないと判断できる場合**は、フェーズ3のユーザー判断を簡略化してもよい（ユーザーに「互換性に問題なく、テストもパスしているためマージします」と一括で伝えて進める）。ただし不安要素がある場合は必ず個別に確認すること。patch 更新は自動マージされるため、既にマージ済みであれば報告のみでよい。

成果物: 各 PR の影響評価レポート。不明点はユーザーに確認すること。

---

## フェーズ3: マージ判断

フェーズ2の影響評価レポートをユーザーに提示し、マージするかどうかの判断を仰ぐ。

- 「マージする」場合 → フェーズ4に進む
- 「様子を見る / 後回し」の場合 → スキップして次の PR へ
- 「詳細を確認したい」場合 → 追加調査を行い再報告

判断の参考として、以下の質問をユーザーに投げかけてもよい:
- この Gem の更新を急ぐ理由はあるか（脆弱性対応など）
- 手動での対応（コード修正）が必要か
- 他の PR との依存関係はあるか（複数の Gem を同時に更新する必要があるか）

---

## フェーズ4: ローカル検証

マージ判断の PR について、ローカル環境で検証する。

### 4.1 ブランチの取得と依存関係更新

```bash
# 最新の main を取得
git checkout main && git pull origin main

# Dependabot のブランチをローカルにチェックアウト
gh pr checkout <PR番号>

# Gem を実際にインストール
bundle install
```

### 4.2 テスト実行

```bash
bin/rails test
```

差分が `Gemfile.lock` のみ等の低リスク更新では、関連テストと `bundle exec srb tc` に止めてよい。**全体テスト・システムテストは全 PR マージ後の main で各1回実行**し、PR ごとにフルテストを繰り返さない。

失敗した場合は、原因を特定してユーザーに報告する:
- Dependabot の変更自体に問題がある（互換性のない API 変更など）
- 既存のテストが不安定（flaky）
- ローカル環境の問題

### 4.3 Rubocop 実行

```bash
bin/rubocop
```

`bin/rubocop` と `bundle exec srb tc` は相互に独立しているため、同一メッセージで並列実行してよい。

### 4.4 セキュリティスキャン

```bash
bin/brakeman --no-pager
bin/bundler-audit
bin/importmap audit
```

CI（`.github/workflows/ci.yml`）は `main` への push 時のみ実行され、`bin/brakeman --no-pager`・`bin/bundler-audit`・`bin/importmap audit` は CI では実行されない。3つのスキャンはローカルで実施し、相互に独立しているため同一メッセージで並列実行してよい。

### 4.5 追加の動作確認

必要に応じて以下の確認を行う:
- `bin/rails runner 'puts <Gem>::VERSION'` でバージョンが正しく読み込めるか
- `bin/rails runner` で簡単な動作確認（Gem の機能を直接呼び出してエラーがないか）
- 該当 Gem に関連する機能の手動確認が必要と判断した場合、ユーザーにその旨を伝える

### 4.6 検証結果の報告

以下の形式で報告する。**報告は日本語で行う**（中国語など他言語を混入させない）:

```
### 検証結果: PR #<番号>

- ✅ / ❌ bundle install
- ✅ / ❌ bin/rails test（<件数> tests, <件数> assertions, <数> failures, <数> errors）
- ✅ / ❌ bin/rubocop（<件数> offenses）
- ✅ / ❌ bin/brakeman
- ✅ / ❌ bin/bundler-audit
- ✅ / ❌ bin/importmap audit

総評: 問題なし / 問題あり（詳細）
```

検証で問題が見つかった場合、ユーザーに報告して次の指示を仰ぐ。

問題がなければフェーズ5に進む。

---

## フェーズ5: PR マージ・クローズ

```bash
# main ブランチにいることを確認
git branch --show-current

# PR をマージ（マージコミットを作成）
gh pr merge <PR番号> --merge --subject "<コミットメッセージ>" --body "<ボディ>"

# または squash merge の場合
# gh pr merge <PR番号> --squash --subject "<コミットメッセージ>" --body "<ボディ>"
```

patch 更新の自動マージは squash で行われる。手動マージはマージコミットを基本とし、squash を使う場合は事前にユーザーと合意すること。

コミットメッセージは以下の形式を基本とする（日本語）:

```
chore(deps): <Gem名>を<旧バージョン>から<新バージョン>へ更新

<変更の簡潔な説明や breaking change の注意点>
```

### 5.1 マージ後の確認

```bash
# 最新の main を反映
git checkout main && git pull origin main
```

### 5.2 gem RBI の同期（Gemfile.lock 更新時）

Dependabot は `Gemfile.lock` しか変更しないため、RBI のファイル名に埋まっている gem バージョン（`sorbet/rbi/gems/<gem>@<version>.rbi`）がずれると型チェックの前提が崩れる。`sorbet/rbi/gems/` はgit管理外（`.gitignore`）のため、**全 PR のマージ後に main で1回だけ**ローカルで再生成して `srb tc` を確認する。CI でも `bin/tapioca gem` を実行してから `srb tc` するため、コミットは不要:

```bash
bundle install
bin/tapioca gem
bin/tapioca gem --verify   # 「Nothing to do, all RBIs are up-to-date.」を確認
bundle exec srb tc
```

- コミットは不要（`sorbet/rbi/gems/` はgit管理外。CIが実行時に生成する）
- sorbet / sorbet-runtime は RBI を生成しないため、この2つだけの更新なら再生成は不要。
- 全体テスト・システムテスト（最終検証）は1回だけ実施し、コミット前には `.agents/skills/security-check/SKILL.md` の手順に従い**コミット対象の変更ファイル**を対象とした機密情報スキャンを実行する。リポジトリ全体のスキャンはユーザーが明示的に指定した場合のみ実行すること。

---

## フェーズ6: 次の PR へ / 完了報告

未処理の Dependabot PR が残っている場合、フェーズ2に戻り次の PR を処理する。

全 PR の処理が完了したら、全マージ後の main で全体テスト・システムテストを各1回実行し、フェーズ5.2 の RBI 同期を済ませてから、以下の内容をユーザーに報告する。**報告は日本語で行う**（中国語など他言語を混入させない）:

```
## Dependabot PR 処理完了レポート

### 処理結果
| PR | 更新内容 | 結果 |
|----|---------|------|
| #N | gem A x.y → x.z | ✅ マージ |
| #M | gem B x.y → a.b | ⏭️ スキップ（<理由>） |

### マージした PR: N 件
<リスト>

### スキップ / 後回しにした PR: M 件
<リストと理由>

### 残課題・注意点
- 今後注意が必要な変更点
- ドキュメント更新が必要な場合
- デプロイ時の注意点
```

マージ後の main の CI 確認は `.agents/skills/ci-verification/SKILL.md` に従う。

---

## 提案事項

このスキルを初めて実行する際に、以下の提案を行うことを推奨する:

### 1. `.github/dependabot.yml` の見直し

現在は bundler を週次（金曜17:00 JST）で更新する設定である。実ファイルの内容を正とし、更新頻度、対象ブランチ、ラベル、レビュー担当、自動マージなどを変更する必要がある場合は、現在の運用とリスクを確認してからユーザーへ提案する。

### 2. レビューアサイン / 自動マージの運用

本リポジトリでは patch 更新の自動マージ（`.github/workflows/auto-merge-patches.yml`）が既に有効である。minor / major の扱いやレビューア自動アサイン（`reviewers:`）を変更する場合は、現在の運用とリスクを確認してからユーザーへ提案する。

### 3. 依存関係監査の定期実行

CI ではセキュリティ監査（`bin/bundler-audit`・`bin/importmap audit`）は実行されないため、ローカルで定期的に実行する運用を推奨する。脆弱性が検出された場合の対応手順をあらかじめ決めておくことを推奨する。

### 4. AGENTS.md との同期

Dependabot の対象や運用手順を変更した場合は、`AGENTS.md` の説明と同期する。

---

## 注意点

- **ブランチ運用**: このスキルでは `main` ブランチからトピックブランチを作成せず、Dependabot が作成したブランチをそのまま検証・マージする。これは Dependabot PR のマージが依存関係の更新のみであり、アプリケーションコードの修正を伴わないため。
- **複数 PR の同時依存とコンフリクト**: 同じ Gem に対する複数の Dependabot PR（例: major と minor）が同時に開いている場合、古い方を先にマージすると新しい方がコンフリクトする可能性がある。`Gemfile.lock` の `CHECKSUMS` は全 gem の sha256 を列挙するため、無関係な gem 同士でも行が隣接しているとコンフリクトする。その場合は `gh pr comment <PR番号> --body "@dependabot rebase"` を投稿してベースブランチを最新 main に更新させ、**ヘッド更新後に関連検証を再実行してから**マージする。自分でコンフリクト解消した結果を Dependabot ブランチへ push しないこと。
- **手動修正の必要性**: Dependabot が自動生成した変更だけでは不十分で、アプリケーションコードの修正が必要になる場合がある。その場合は通常のトピックブランチを作成して修正すること（本スキルの範囲外）。修正でユーザー向け文言を変更する場合は `.agents/skills/translation/SKILL.md` に従うこと。
- **テストが落ちた場合**: Dependabot の変更でテストが落ちた場合、アップストリームの互換性問題である可能性が高い。`git bisect` や CHANGELOG を詳細に確認し、原因を特定してユーザーに報告すること。
