---
name: internationalization
description: tech_notesの国際化・多言語化を行うためのスキル。対応locale（ja/en）のビュー、flash、コントローラ、モデルのバリデーション、メーラー、JavaScriptの文言をI18nへ移行し、ヘッダーの言語切替との整合、翻訳品質、テスト、未翻訳文言の検出まで扱う。
---

# 国際化（多言語化）

国際化・多言語化の依頼を受けた場合は、この手順に従うこと。実装が必要な場合は `internationalization-implementer` エージェントを起動して委譲する。

本スキルが実行されたら、定義済みのサブエージェントを積極的に使うこと。
特に
* 設計： solution_architect
* コードレビュー: code_reviewer
* データベースレビュー : database_reviewer
* ドキュメント更新 : documentation_manager
* Railsコーディング : rails_implementer
* フロントエンドコーディング : frontend_implementer
* セキュリティレビュー : security_auditor
* テスト : test_engineer
* git, github 操作 : repository_operator
* 国際化・多言語化 : internationalization-implementer

の使用を推奨する。
他のエージェントについても必要に応じて起動して作業を進めてください。
各サブエージェントが使用するLLMモデルについては、各サブエージェントで定義されているモデルを使用すること。
特に本スキルを実行するときは、サブエージェント（internationalization-implementer）に積極的に委譲すること。

## 基本方針

- 本プロジェクトの対応localeは `config/locales/ja.yml`、`config/locales/en.yml` から確認した **ja / en**、既定localeは `config/application.rb` で設定された **`:en`**（`available_locales = [:en, :ja]`、`fallbacks = [:en]`）である。対象言語の追加・変更の指定がない場合は既存設定を調査し、言語や文体を勝手に確定しない。
- `I18n.t`、`t`、Rails標準の翻訳キーを使い、ビューやRubyコードに表示文言を直書きしない。
- 翻訳キーは画面・機能の責務が分かる名前にする。文脈、敬語、複数形、文字数制約が異なる文言は分ける。
- 文字列補間は翻訳値側で行い、ユーザー入力をHTMLとして解釈させない。HTMLを含む翻訳は必要性とエスケープを確認する。
- 日付、時刻、数値、タイムゾーン、複数形、単位をロケールに応じて表示し、固定形式の手作業による結合を避ける。
- 翻訳対象のユーザー向け文言と、ログ・監査記録・内部識別子を区別し、後者は不要に翻訳しない。
- 記事タイトル・本文などDBに保持される翻訳（`post_translations`）と、localeファイルで管理するUI文言を混同せず、それぞれ既存の方式に従う。

## 調査

実装前に `AGENTS.md`、`config/application.rb` のi18n設定、`config/locales/`、I18n関連コードを確認する。さらに、コントローラ、ビュー、ヘルパー、モデル、バリデーション、サービス、メーラー、通知、Stimulus／JavaScriptを横断して、次の直書き文言を検索する。

- `flash`、`redirect_to`、`render` のエラー、`errors.full_messages`
- フォームラベル、プレースホルダー、ボタン、ページタイトル、空状態、確認ダイアログ
- メール本文（例: `comment_mailer` の新規コメント通知）、ユーザーへの状態・権限・入力エラーの説明
- ジョブ経由でユーザーに通知する文言がある場合は、その直書き文言（本プロジェクトにジョブ通知基盤を新設する前提で断定しない）

既存の言語切替の仕組み（`app/views/shared/_header.html.erb` の `language_select` ドロップダウンとStimulusの `locale` コントローラ、`LocaleController#update`、`ApplicationController#switch_locale`／`determined_locale` によるURLの `/:locale` プレフィックス・`cookies.permanent[:locale]`・Accept-Languageフォールバック）を確認し、新規範囲も同規約に合わせる。既存テストの固定文言アサーション、locale切り替え、未翻訳時の挙動も確認する。言語や画面仕様が `docs/requirements.md`、`docs/images/` にある場合は、仕様との不整合を整理する。

## 実装手順

1. localeの一覧、既定locale、利用可能locale、選択値の検証、リクエストごとの適用範囲を設計する。ユーザー入力をそのまま `I18n.locale=` に渡さない（既存の `I18n.available_locales` による検証を維持する）。
2. 既存の切り替え規約（URLプレフィックス、永続Cookie、Accept-Language、不正値・未指定時の `:en` フォールバック、ログイン前後・リダイレクト後の挙動）に合わせて実装し、規約から外れる挙動は定義してから変更する。
3. 翻訳ファイルを機能単位で整理し、`helpers`、`activerecord.errors`、日時・数値などRails標準キーを活用する。Stimulus向け文言は既存の `js.*` キー（`config/locales/ja.yml`・`en.yml` の `js:` 配下）の命名に合わせる。
4. コントローラのflash、サービス、メーラー、通知ではキーと補間値を渡し、文言を直書きしない（例: `t("flash.admin.posts.saved")`、`t("flash.comments.created")`）。
5. JavaScriptに文言が必要な場合は、サーバーから安全に渡す方法または既存の翻訳連携方法を使い、JSへ翻訳文を重複定義しない。
6. 各localeで自然な翻訳、補間値、複数形、アクセシビリティ用ラベル、画面幅による崩れを確認する。

## テスト・検証

- 各対象locale（ja/en）で主要画面、成功・失敗flash、バリデーション、メール／通知を確認する。
- 固定文言アサーションを対象localeの期待値へ更新し、言語切り替え、未対応locale、不正locale、補間、複数形を回帰テストする。
- 翻訳キーの不足・誤り、直書き文言、HTML安全性、ユーザー入力の未エスケープを検査する。
- コード変更後は `.agents/skills/translation/SKILL.md` に従い、全対応localeで未翻訳キー・直書き文言がなくなるまで translation エージェントで翻訳完全性を確認する。
- Ruby、Rails、テスト、JavaScript、設定を変更した場合は `.agents/skills/code-change-verification/SKILL.md` に従う。仕様書同期が必要なら `documentation_manager` を明示的に起動する。
- コミット前には `.agents/skills/security-check/SKILL.md` を実行し、翻訳ファイルにも秘密情報や個人情報を含めない。

## 完了条件

対象範囲のユーザー向け文言が翻訳可能で、各対応localeで自然に表示されること。localeの選択・不正値・未翻訳キーが安全に扱われ、関連テストと必要な静的解析が通過し、未対応範囲が明確に報告されていること。
