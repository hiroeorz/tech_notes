---
name: codex-review
description: PR作成後にCodexへ「@codex レビューお願い」を依頼し、5シグナルをポーリングして指摘の妥当性を検証し、fix: 修正ループの後にマージコミットでmainへマージして後片付けする。PRレビュー対応、Codexレビュー対応、マージ、後片付けに使用する。
---

PRを作成した後は、このスキルの手順に従いCodexの自動レビューを受け、結果に応じて対応した後にmainへマージして後片付けを行うこと。

## 前提

- PRは作成済みで、ブランチはリモートにプッシュ済みであること
- Codex（`chatgpt-codex-connector`）はPRに「@codex レビューお願い」とコメントすると、数分後（目安5分）にレビュー結果をコメントとして投稿する
- PR作成・draft ready時はCodexが自動で初回レビューを行うことを基本とする（付かない場合は明示依頼する）。2回目以降（修正push後の再レビュー）は自動で付かないため、「@codex レビューお願い」の明示投稿が必要である
- マージはマージコミット方式（`gh pr merge --merge`）を使用する。squash・rebaseは使わない
- このスキルの使用指示は、フロー内でのマージの明示委譲を含む。ただし、下記の例外状況では必ずユーザーに確認してからマージすること
- 本プロジェクトのCIは `main` への `push`（マージ含む）時のみ実行される（`.github/workflows/ci.yml`）。PRブランチではCIが走らないため、PRブランチのCI結果は存在しない。CI確認はマージ後に `.agents/skills/ci-verification/SKILL.md` に従って行う

## ワークフロー

```
PR作成完了（初回レビューは自動で付く）
  ↓
自動レビューがなければ「@codex レビューお願い」を投稿
  ↓
Codexのレビューコメントを待機（ポーリング）
  ↓
コメント到着 → 各指摘の妥当性を検証
  ↓
妥当な指摘あり → 修正 → コミット(fix:) → プッシュ → 再レビュー依頼 ↺
  ↓
妥当な指摘なし → mainへマージ → 後片付け → 完了報告 → 終了
```

## フェーズ1: レビュー依頼

まずCodexのレビューが付いているか確認する（issue comments・インライン・reviews・PR本体の👍の4箇所）。**PR本体の👍が付いていれば「指摘なし」完了なので依頼は不要**。付いていない場合、または完了報告コメントの `Reviewed commit` が現在のHEADと一致しない場合のみ依頼コメントを投稿する:

```bash
gh pr comment <PR番号> --body "@codex レビューお願い"
```

- PR作成・draft ready時の初回レビューは自動で付くことが多いが、付かないこともある。10分待ってもレビューが無ければ明示依頼へ切り替える
- **PR本体への👍は「指摘なし」の完了シグナルとしてそのまま扱ってよい**（Reviewed commit の記載は無くてもよい）。ただし、👍が出た後に push した場合は評価対象が古くなるため、最新HEADで再依頼する
- **過去ラウンドの👍と最新ラウンドの👍を区別する**: 修正push後の再レビューでは、依頼時刻より前に付いたPR本体の👍は過去ラウンドの完了シグナルであり、最新HEADの完了シグナルとして扱わない。最新の依頼時刻を控え、それ以降に生成された完了シグナルのみを判定する
- 2回目以降（修正push後）は自動で付かないため毎回明示投稿が必要である

依頼コメントのID（`issuecomment-<ID>`）と依頼時刻（UTC）を記録しておく（フェーズ2のリアクション確認に使う）。

## フェーズ2: レビューコメントの待機

Codexのレビューは通常5分程度で完了する。**5シグナル**を毎回取得し、**取得したカウントはすべて break 条件に使う**（数えるだけで条件に使わないと完了報告を見逃す）:

1. `issues/<PR番号>/comments`（完了報告 `Codex Review: Didn't find any major issues.` / エラー報告）
2. `pulls/<PR番号>/comments`（インライン指摘。P1/P2バッジで付く）
3. `reviews`（レビュー投稿の state / body）
4. `issues/<PR番号>/reactions`（PR本体への👍。初回自動レビューはここに付き得る）
5. `issues/comments/<依頼コメントID>/reactions`（依頼コメントへの👍。依頼を投稿した場合のみ）

```bash
# 依頼直後にベースラインを取る（since は依頼投稿時刻。PR本体の古い👍を除外するために使う）
since=$(date -u +%Y-%m-%dT%H:%M:%SZ)
# gh api は1ページ最大30件。--paginate で全ページ取得し、--jq がページごとに出力する件数を awk で合算する
issue_base=$(env -u GH_TOKEN gh api --paginate repos/hiroeorz/tech_notes/issues/<PR番号>/comments --jq '[.[] | select(.user.login | startswith("chatgpt-codex-connector"))] | length' | awk '{s+=$1} END {print s+0}')
inline_base=$(env -u GH_TOKEN gh api --paginate repos/hiroeorz/tech_notes/pulls/<PR番号>/comments --jq '[.[] | select(.user.login | startswith("chatgpt-codex-connector"))] | length' | awk '{s+=$1} END {print s+0}')
review_base=$(env -u GH_TOKEN gh pr view <PR番号> --json reviews --jq '[.reviews[] | select(.author.login | startswith("chatgpt-codex-connector"))] | length')

for i in $(seq 1 15); do
  sleep 60
  issue_count=$(env -u GH_TOKEN gh api --paginate repos/hiroeorz/tech_notes/issues/<PR番号>/comments --jq '[.[] | select(.user.login | startswith("chatgpt-codex-connector"))] | length' | awk '{s+=$1} END {print s+0}')
  inline_count=$(env -u GH_TOKEN gh api --paginate repos/hiroeorz/tech_notes/pulls/<PR番号>/comments --jq '[.[] | select(.user.login | startswith("chatgpt-codex-connector"))] | length' | awk '{s+=$1} END {print s+0}')
  review_count=$(env -u GH_TOKEN gh pr view <PR番号> --json reviews --jq '[.reviews[] | select(.author.login | startswith("chatgpt-codex-connector"))] | length')
  pr_plus=$(env -u GH_TOKEN gh api --paginate repos/hiroeorz/tech_notes/issues/<PR番号>/reactions --jq "[.[] | select(.user.login | startswith(\"chatgpt-codex-connector\")) | select(.content == \"+1\") | select(.created_at > \"$since\")] | length" | awk '{s+=$1} END {print s+0}')
  plus_count=$(env -u GH_TOKEN gh api --paginate repos/hiroeorz/tech_notes/issues/comments/<依頼コメントID>/reactions --jq '[.[] | select(.user.login | startswith("chatgpt-codex-connector")) | select(.content == "+1")] | length' 2>/dev/null | awk '{s+=$1} END {print s+0}')
  echo "try $i: issue=$issue_count inline=$inline_count review=$review_count pr_plus=$pr_plus plus=$plus_count"
  if [ "$issue_count" -gt "$issue_base" ] || [ "$inline_count" -gt "$inline_base" ] || [ "$review_count" -gt "$review_base" ] || [ "$pr_plus" -gt 0 ] || [ "$plus_count" -gt 0 ]; then
    break
  fi
done
```

- カウントは「新着あり/なし」の判定に使い、**最終判定は本文**で行う（件数だけでは「指摘なし」と `Something went wrong` を区別できない）
- `gh api` は1ページ最大30件のため、ベースライン・ポーリング・最終ダンプでは `--paginate` を付けて全ページを対象にする（`--paginate` と `--jq` の併用時はページごとに出力されるため `awk` で合算する）
- ループを抜けたら（時間切れでも）**5箇所すべてをフィルタなしで全件ダンプ（`gh api` は `--paginate` を付ける）**して本文を確認する:
  - issue comments に `Didn't find any major issues` → 指摘なし完了。ただし**依頼時刻以降に投稿されたもの、または `Reviewed commit:` が現在のHEADと一致するもの**のみ有効とする。どちらも満たさない過去ラウンドの完了コメントは無効で、最新ラウンドの完了シグナルとは扱わない（タイムアウト時は全件ダンプのうえユーザーに報告する）
  - PR本体に 👍 → 指摘なし完了（Reviewed commit の記載は無くてもよい）。ただし依頼時刻より前に付いた古い👍は無効で、最新ラウンドの完了シグナルとは扱わない。古い👍しかない場合は issue comments の完了報告を待ち、タイムアウト時は全件ダンプのうえユーザーに報告する
  - issue comments に `Something went wrong` → `@codex review` で再依頼する
  - インラインに Pバッジ（P1/P2）→ 指摘あり。妥当性を検証する
  - 👀（eyes）リアクションのみ → 処理中。完了ではない
- `gh` の一時的な空出力や jq 実行時エラー（exit 0 のまま空 stdout）を「新着あり」と誤判定しない。出力が JSON 配列であることを確認してから判定する
- 待機中の進捗報告は不要。コメント到着またはタイムアウト時に報告する
- 15分待っても完了報告が来ない場合は、**ユーザーへ報告する前に必ず5箇所の全件ダンプで本文を確認**し、それでも無ければ状況を報告して指示を仰ぐ

## フェーズ3: 指摘の妥当性検証

コメントに含まれる各指摘を読み、妥当性を判断する:

| 判断 | 基準 | 対応 |
|---|---|---|
| 妥当 | バグ、N+1、情報漏洩、境界条件の抜け、要件未達、テスト不足など実害がある指摘 | 修正チケット化してフェーズ4で対応 |
| 妥当でない | 誤検知、仕様上の意図的挙動、本変更のスコープ外 | 対応せず、理由を添えてユーザーに報告し判断を仰ぐ |

妥当な指摘が1件でもある場合はフェーズ4へ、妥当でない指摘のみの場合はユーザーの判断を仰いでからフェーズ5へ進む。

## フェーズ4: 修正と再レビュー

1. 妥当な指摘ごとに修正を実装する
2. ローカルで関連テストと静的解析を実行し、通過を確認する（変更内容に応じて `.agents/skills/code-change-verification/SKILL.md` に従い `bin/rubocop`、`bundle exec srb tc`、関連テストなどを選択する）
3. コミット前には必ず `.agents/skills/security-check/SKILL.md` の手順に従い機密情報スキャンを実行する（**コミットより前に実行する**。コミット後に実行すると機密情報がGit履歴へ記録された後での検出となり、履歴書き換えなしでは除去できない）
4. コミットする（日本語メッセージ、`fix:` プレフィックス）:

```bash
git add <該当ファイル>
git commit -m "fix: <指摘内容の概要>（codexレビュー対応）"
```

5. プッシュし、フェーズ1へ戻って再レビューを依頼する:

```bash
git push origin <ブランチ名>
gh pr comment <PR番号> --body "@codex レビューお願い"
```

PRブランチへのプッシュではCIは実行されない（CIは `main` への `push` 時のみ）。再レビュー依頼をCI完了までブロックする必要はない（PRブランチで確認できるCIはない）。

妥当な指摘がなくなるまでループする。

## フェーズ5: mainへのマージと後片付け

妥当な指摘が残っていないことを確認したら、mainへマージして後片付けを行う。**マージ前に、最終スナップショットで上位スキルの全体チェック（全テスト、UI変更がある場合はシステムテスト）が通過済みであることを確認する。**レビュー指摘の `fix:` で検証が陳腐化している場合は、マージ前に全体チェックを再実行する。まだ実施していない場合も、マージ前に上位スキルの手順（`feature-implementation` フェーズ9.4/9.5、`bug-fix` の全体チェック）に従って実施する。

1. マージ:

```bash
gh pr merge <PR番号> --merge
```

2. 後片付け:

```bash
git checkout main
git pull origin main
git branch -d <ブランチ名>
git push origin --delete <ブランチ名>
```

3. mainのCI確認: マージ後、`.agents/skills/ci-verification/SKILL.md` の手順に従いmainのCIを確認する

4. ユーザーに完了を報告する（マージされたPRのURL）。**報告は日本語で行う**（中国語など他言語を混入させない）

### マージ前にユーザーへ確認が必要な例外状況

- 妥当でない指摘のみで、ユーザーの判断が未取得の場合
- main のCIが失敗したまま未修正で、その状態のまま追加変更をマージしようとしている場合
- PRに他者（ユーザー自身など）のレビューや保留コメントがある場合
- マージ後処理の影響が大きいと判断される場合（例: mainの保護、リリース直前）

## 注意事項

- レビュー依頼は指摘対応のたびに再依頼すること。対応したのに再依頼を忘れると、対応漏れのまま進むことになる
- Codexの指摘はインラインのpull request commentsとして付くことが多いため、フェーズ2では必ず `pulls/<PR番号>/comments` も取得すること
- 待機ループでは**issue comments・インライン・reviews・PR本体の👍・依頼コメントの👍の5シグナルを取得し、すべてを break 条件に使う**。特に issue comments は「指摘なし完了」の通知先になるため取りこぼしやすい
- 「指摘なし」は**PR本体への👍**・依頼コメントへの👍・**issue comments の完了報告**のいずれでも来る。特に **PR本体への👍は「指摘なし」の完了シグナルとしてそのまま扱ってよい**（Reviewed commit の記載を待って再依頼を繰り返さない）。ただし 👍 の後に push した場合は最新HEADで再依頼し、依頼時刻より前に付いた過去ラウンドの👍は無効として扱う。issue comments の完了報告も同様に、依頼時刻以降の投稿または現在のHEADを指すものだけを有効とする
- 完了報告に `Reviewed commit` が記載されており、現在のHEADと一致しない場合は最新HEADで再依頼すること
- タイムアウト時や判定に迷った場合は、ユーザーへ報告する前に5箇所すべてをフィルタなしで全件ダンプして本文を確認すること
- 指摘が妥当でないと判断した場合は、自己判断でスキップせず必ずユーザーに報告して判断を仰ぐこと
- 修正コミットは `fix:` プレフィックス、日本語メッセージで行うこと
- コミット前の機密情報スキャンは必須（コミットより前に実行すること）
- プッシュ後の再レビュー依頼をCI完了まで待つ必要はない（CIは `main` への push 時のみ実行され、PRブランチでは確認できない）。CI確認はマージ後に `ci-verification` で行う
- `git reset --hard`、`git clean`、force push、履歴書き換えは実行しない
- 待機中にユーザーへ進捗を報告する必要はない。コメント到着、タイムアウト、マージ完了時に報告する
