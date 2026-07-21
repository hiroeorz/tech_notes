---
name: browser-check
description: Playwright MCPを使用してWSL上のRailsアプリの表示を確認する。UI変更後、レスポンシブ表示、テーマ、コンソールエラー、アクセシビリティを検証する場合に使用。Use ONLY when Playwright MCPが有効で、Railsサーバーが起動している場合。
---

# Skill: browser-check

Playwright MCPを使用して、WSL環境で動作するRailsアプリのブラウザ表示を確認します。

## 前提条件

- Playwright MCPが `opencode.json` で有効になっている
- Railsサーバーが起動している（`bin/rails server -b 0.0.0.0 -p 3000`）
- Node.jsがWSLにインストールされている

## 確認手順

### 1. Railsサーバーの確認・起動

```bash
# 起動しているか確認
pgrep -f "rails server" || bin/rails server -b 0.0.0.0 -p 3000 -d
```

### 2. ページ表示確認

`browser_navigate` で対象ページを開く：

```
browser_navigate → http://127.0.0.1:3000/<対象URL>
```

### 3. デスクトップ表示のスクリーンショット

```
browser_screenshot → デスクトップ幅 (1280x720)
```

### 4. モバイル表示のスクリーンショット

レスポンシブ対応が必要なページはモバイル幅でも確認：

```
browser_resize → 375x812 (iPhone X/11 相当)
browser_screenshot
```

### 5. コンソールエラー確認

```
browser_console_messages → level: "error"
```

エラーがあれば原因を特定し修正。

### 6. ネットワークエラー確認

```
browser_network_requests → ステータスコード4xx/5xxを確認
```

### 7. ダークテーマ確認（該当ページ）

テーマ切り替えがあるページは、ライト／ダーク両方で確認。

### 8. フォーム操作確認（該当ページ）

フォームがあるページは、`browser_fill_form` と `browser_click` で入力・送信フローを確認。

### 9. クリーンアップ

```
browser_close → ブラウザを閉じる
```

## 確認項目チェックリスト

- [ ] ページが正常に読み込まれる
- [ ] デスクトップ幅で表示崩れがない
- [ ] モバイル幅で表示崩れがない
- [ ] コンソールエラーがない
- [ ] ネットワークエラーがない
- [ ] ライト／ダークテーマが正常に動作
- [ ] フォーム操作が正常（該当する場合）
- [ ] アクセシビリティ要素（ラベル、alt属性、ARIA）が適切

## 注意事項

- Playwright MCPのブラウザはWSL内でheadless動作します
- Windows側のブラウザには表示されません
- 視覚的な確認はスクリーンショット画像を通じて行います
- `--caps vision` により座標ベースのクリックも可能です
