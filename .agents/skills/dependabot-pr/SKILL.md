---
name: dependabot-pr
description: GitHub Dependabot が起票したプルリクエストの調査・検証・マージまでを一貫して行う。古い PR から順に処理し、ユーザーの判断を仰ぎながら進める。
---

Dependabot が起票した PR を処理するよう指示された場合、または定期的な依存関係更新の一環として、このスキルの手順に従うこと。

**各フェーズにおいて、変更内容や影響範囲が不明瞭な場合は、その時点でユーザーに確認し、明確にしてから次に進むこと。**

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
全 PR 処理後の報告
```

---

## フェーズ0: 前提条件の確認

以下のツールが利用可能であることを確認する。不足があればユーザーに知らせて対応を仰ぐ。

- `gh` CLI がインストールされ、GitHub 認証が済んでいること
- `git` が正しく設定され、リモートリポジトリにアクセスできること
- ローカル環境で `bin/rails test` が実行可能な状態であること（bundle 済み、DB 準備済み）
- `bundle audit` が Gemfile.lock の読み取りに成功すること

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

このリポジトリの Dependabot 設定ファイル（`.github/dependabot.yml`）が存在しない場合、以下の点をユーザーに報告する:
- Dependabot が有効化されていない可能性がある
- 必要に応じて `.github/dependabot.yml` の作成を提案する（スキル末尾の「提案事項」参照）

### 1.2 全体像の報告

取得した PR 一覧をユーザーに以下の形式で報告する:

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

以下の手順を古い PR から順に1件ずつ実行する。

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

以下の形式でユーザーに報告する（各 PR ごと）:

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

**パッチ / マイナーでコード内の使用箇所が単純かつ互換性に問題ないと判断できる場合**は、フェーズ3のユーザー判断を簡略化してもよい（ユーザーに「互換性に問題なく、テストもパスしているためマージします」と一括で伝えて進める）。ただし不安要素がある場合は必ず個別に確認すること。

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

失敗した場合は、原因を特定してユーザーに報告する:
- Dependabot の変更自体に問題がある（互換性のない API 変更など）
- 既存のテストが不安定（flaky）
- ローカル環境の問題

### 4.3 Rubocop 実行

```bash
bin/rubocop
```

### 4.4 セキュリティスキャン

```bash
bin/brakeman --no-pager
bin/bundler-audit
```

### 4.5 追加の動作確認

必要に応じて以下の確認を行う:
- `bin/rails runner 'puts <Gem>::VERSION'` でバージョンが正しく読み込めるか
- `bin/rails runner` で簡単な動作確認（Gem の機能を直接呼び出してエラーがないか）
- 該当 Gem に関連する機能の手動確認が必要と判断した場合、ユーザーにその旨を伝える

### 4.6 検証結果の報告

以下の形式で報告する:

```
### 検証結果: PR #<番号>

- ✅ / ❌ bundle install
- ✅ / ❌ bin/rails test（<件数> tests, <件数> assertions, <数> failures, <数> errors）
- ✅ / ❌ bin/rubocop（<件数> offenses）
- ✅ / ❌ bin/brakeman
- ✅ / ❌ bin/bundler-audit

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

コミットメッセージは以下の形式を基本とする:

```
chore(deps): bump <gem-name> from <旧バージョン> to <新バージョン>

<変更の簡潔な説明や breaking change の注意点>
```

### 5.1 マージ後の確認

```bash
# 最新の main を反映
git checkout main && git pull origin main
```

---

## フェーズ6: 次の PR へ / 完了報告

未処理の Dependabot PR が残っている場合、フェーズ2に戻り次の PR を処理する。

全 PR の処理が完了したら、以下の内容をユーザーに報告する:

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

---

## 提案事項

このスキルを初めて実行する際に、以下の提案を行うことを推奨する:

### 1. `.github/dependabot.yml` の作成

現在このリポジトリには Dependabot の設定ファイルが存在しない。Dependabot による自動更新を受け取るには、以下の設定ファイルを `.github/dependabot.yml` に作成する必要がある:

```yaml
version: 2
updates:
  - package-ecosystem: "bundler"
    directory: "/"
    schedule:
      interval: "weekly"
      day: "monday"
      time: "09:00"
      timezone: "Asia/Tokyo"
    open-pull-requests-limit: 10
    labels:
      - "dependencies"
      - "ruby"
```

ユーザーに上記を提案し、作成するかどうか確認すること。

### 2. レビューアサイン / 自動マージの検討

PR の数が増えてきた場合、以下の運用を検討してもよい:
- Dependabot にレビューアを自動アサインする設定（`reviewers:`）
- patch 更新のみ自動マージする設定（`target-branch:` + GitHub Actions の auto-merge）

### 3. `bundle audit` の定期実行

CI ですでに `bin/bundler-audit` は実行されている（AGENTS.md より）。脆弱性が検出された場合の対応手順をあらかじめ決めておくことを推奨する。

### 4. AGENTS.md への追記

本スキルに関する参照を AGENTS.md に追記することを提案する（「Dependabot PR の処理は `.agents/skills/dependabot-pr/SKILL.md` の手順に従う」といった一文）。

---

## 注意点

- **ブランチ運用**: このスキルでは `main` ブランチからトピックブランチを作成せず、Dependabot が作成したブランチをそのまま検証・マージする。これは Dependabot PR のマージが依存関係の更新のみであり、アプリケーションコードの修正を伴わないため。
- **複数 PR の同時依存**: 同じ Gem に対する複数の Dependabot PR（例: major と minor）が同時に開いている場合、古い方（minor）を先にマージすると新しい方（major）がコンフリクトする可能性がある。その場合は major PR のベースブランチを最新の main に更新する必要がある。
- **手動修正の必要性**: Dependabot が自動生成した変更だけでは不十分で、アプリケーションコードの修正が必要になる場合がある。その場合は通常の feature ブランチを作成して修正すること（本スキルの範囲外）。
- **テストが落ちた場合**: Dependabot の変更でテストが落ちた場合、アップストリームの互換性問題である可能性が高い。`git bisect` や CHANGELOG を詳細に確認し、原因を特定してユーザーに報告すること。
