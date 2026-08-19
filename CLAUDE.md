# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## このリポジトリについて

Claude Code に文章スタイルルールを守らせる執筆ガードレール plugin です。構成と仕組みは README.md を参照してください。

## ルールの正本と生成物

- ルールの正本は `plugins/writing-style/skills/style-review/references/rules.md` の1ファイルです
- `plugins/writing-style/hooks/hooks.json` は `scripts/generate-hooks.sh` による生成物です。直接編集せず、rules.md または generate-hooks.sh を編集してから再生成してください
- rules.md か generate-hooks.sh を変更したら、必ず `bash scripts/generate-hooks.sh` を実行し、生成された hooks.json を同じ commit に含めてください

## Versioning（semver）

version は `plugins/writing-style/.claude-plugin/plugin.json` と `.claude-plugin/marketplace.json` の2箇所を必ず揃えます。この repo を参照する配布用カタログを別途運用している場合は、そちらの version も追随させます。

- **major**: 互換性を壊す変更（構成の作り直し、設定形式の変更など）
- **minor**: 検証の判定が変わる変更（rules.md へのルール追加・削除、検証手順の変更、hook 構成の変更）
- **patch**: 判定を変えない bugfix・誤字修正のみ

## 動作確認

hooks.json の変更を試すときは、対象ワークスペースの `.claude/settings.local.json` に PreToolUse 部分をコピーして再起動するとローカルで検証できます。hooks の変更反映にはセッションの再起動が必要です。
