#!/bin/bash
# hooks.json を rules.md から生成する。
#
# ルールの正本は plugins/writing-style/skills/style-review/references/rules.md の1つ。
# 検証エージェント（agent hook）は許可プロンプトを出せない実行文脈で動くため、
# ワークスペース外のファイル（プラグイン実体や ~/.claude/ 配下）を Read できない（実測）。
# また ${CLAUDE_PLUGIN_ROOT} は agent hook の prompt フィールドでは置換されない（実測）。
# そのためルール全文をプロンプトへ埋め込む。ルール改定時はこのスクリプトを実行して
# hooks.json を再生成し、rules.md と一緒にコミットすること。
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
plugin="$repo_root/plugins/writing-style"
rules="$(cat "$plugin/skills/style-review/references/rules.md")"

header='これから実行されようとしているファイル書き込みイベント（PreToolUse）: $ARGUMENTS

この書き込みを実行してよいか、文章スタイルの観点で事前に検証する。書き込み予定の内容は tool_input に入っている（Write は content、Edit は new_string または edits 配列の各 new_string）。手順:
1. tool_input.file_path の拡張子が .md / .txt 以外の場合、またはパスに CLAUDE.md・MEMORY.md・/.claude/ を含む場合は、検査対象外として許可する
2. 文脈把握のため、編集前の現行ファイルを読む。まず tool_input.file_path を Read する。全文が返れば（約2,000行以内）それを使う。ファイルが長く途中までしか読めない場合:
   - Edit の場合は、Grep（-n）で tool_input.old_string の先頭行がファイルの何行目かを特定し、その行を中心に約1,000行を1回の Read で読む（offset = 該当行 - 500、limit = 1000。offset が負なら 0）。あわせて文書冒頭の約500行（タイトル・結論・全体像が置かれる範囲）を読む
   - Write（全文置き換え）の場合は、文書冒頭の約1,000行を読む
   - ファイルが存在しない場合（新規作成）は、手順4に移る
3. 書き込み予定の内容を、末尾のルールに照らして検査する。文レベルのルールに加えて、読めた範囲を使って次の文脈整合も検査する:
   - 書き込み箇所が直前・直後の段落と論理的に接続するか（唐突な話題転換・指示語の宙づりがないか）
   - 書き込み内容が、既読の範囲の他の箇所と重複しないか（同じ主張・説明の言い直しは冗長ルールの違反）。重複の照合は、書き込み箇所と同一セクション・隣接セクション・文書冒頭の結論部を重点とし、全文の網羅的な相互比較は行わない
   - 書き込み内容が、置かれるセクションのトピックから外れないか
4. 現行ファイルを読めない場合は、書き込み予定の内容だけを文レベルのルールで検査する（文脈整合の検査は省略する）
5. 違反が1件以上あれば書き込みを拒否（不合格）とし、理由に違反ごとの「原文の引用・違反したルール・修正案」を列挙する。違反がなければ許可（合格）とする
6. 拒否の場合、理由の末尾に次の文を一字一句そのまま含める: 「【編集した本体エージェントへ: この書き込みは実行されていません。指摘を反映した内容で再度 Write/Edit を実行してください。同じ編集が3回連続で拒否された場合は、作業を止めてユーザーに相談してください。】」

検査対象外: コードブロック（``` 内）、引用ブロック（> 行）、URL、脚注定義、mermaid 図のソース、JSON などのコード片。見出しの体言止めは違反にしない。書き込み箇所の外にもともとある違反は指摘しない。

=== 文章スタイルルール ===
'

jq -n --arg prompt "${header}${rules}" '{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|resume|clear|compact",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/bin/inject-rules.sh",
            "timeout": 10,
            "statusMessage": "文章スタイルルールを読み込み中"
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "agent",
            "if": "Write(**/*.md)",
            "prompt": $prompt,
            "model": "claude-sonnet-5",
            "timeout": 90,
            "statusMessage": "文章スタイルを書き込み前に検証中"
          },
          {
            "type": "agent",
            "if": "Write(**/*.txt)",
            "prompt": $prompt,
            "model": "claude-sonnet-5",
            "timeout": 90,
            "statusMessage": "文章スタイルを書き込み前に検証中"
          },
          {
            "type": "agent",
            "if": "Edit(**/*.md)",
            "prompt": $prompt,
            "model": "claude-sonnet-5",
            "timeout": 90,
            "statusMessage": "文章スタイルを書き込み前に検証中"
          },
          {
            "type": "agent",
            "if": "Edit(**/*.txt)",
            "prompt": $prompt,
            "model": "claude-sonnet-5",
            "timeout": 90,
            "statusMessage": "文章スタイルを書き込み前に検証中"
          }
        ]
      }
    ]
  }
}' > "$plugin/hooks/hooks.json"

echo "生成完了: $plugin/hooks/hooks.json"
