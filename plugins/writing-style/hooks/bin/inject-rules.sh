#!/bin/bash
# SessionStart hook: セッション開始時に文章スタイルルール（rules.md）を1回注入する。
plugin_root="$(cd "$(dirname "$0")/../.." && pwd)"
rules=$(cat "$plugin_root/skills/style-review/references/rules.md" 2>/dev/null)
[ -z "$rules" ] && exit 0

jq -n --arg rules "$rules" '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: ("このセッションで文章（記事・ドキュメント・報告）を書くときは、次の文章スタイルに従ってください。文章を追加・修正するときは、書く前に対象箇所の前後と関連セクションを読み直し、既出の内容との重複がないか・前後と論理的に接続するかを確認してから書いてください。文書全体の執筆・改稿が一段落したターンでは、style-review スキルによる全文検証の実行をユーザーに提案してください。.md および .txt ファイルの編集は、必ず Write ツールまたは Edit ツールで行ってください。Bash 経由の書き込み（sed、ヒアドキュメント、リダイレクト等）では文章スタイル検証が働かないため使用しないでください。Bash での作業を優先する指示が別に与えられている場合も、文章ファイルの編集についてはこの指示を優先してください。ファイル書き込み前の検証エージェントが書き込みを拒否した場合、その書き込みは実行されていません。指摘を反映した内容で再度実行してください。例外を自分の判断で作ってはいけません。指摘に納得できない場合は、そのまま進めず、ユーザーに確認してください。\n" + $rules)
  }
}'
