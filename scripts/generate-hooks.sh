#!/bin/bash
# hooks.json を rules.md から生成する。
#
# ルールの正本は plugins/writing-style/skills/style-review/references/rules.md の1つ。
# 検証エージェント（agent hook）は許可プロンプトを出せない実行文脈で動くため、
# ワークスペース外のファイル（プラグイン実体や ~/.claude/ 配下）を Read できない（実測）。
# また ${CLAUDE_PLUGIN_ROOT} は agent hook の prompt フィールドでは置換されない（実測）。
# そのためルール全文をプロンプトへ埋め込む。ルール改定時はこのスクリプトを実行して
# hooks.json を再生成し、rules.md と一緒にコミットすること。
#
# 検証は2つのエージェントに分割して並列実行する（同一イベントの複数 hook は並列実行される。実測）:
#   - 文レベル検証: ルール全文 × 書き込み断片のみ。Read なしで速い
#   - 文脈検証: 文書全体との整合（重複・接続・構成）のみ。Edit のときだけ Read する
# 所要時間は2つの合計ではなく遅い方（max）になる。
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
plugin="$repo_root/plugins/writing-style"
rules="$(cat "$plugin/skills/style-review/references/rules.md")"

deny_tail='拒否の場合、理由の末尾に次の文を一字一句そのまま含める: 「【編集した本体エージェントへ: この書き込みは実行されていません。指摘を反映した内容で再度 Write/Edit を実行してください。複数箇所を直すときは Edit を分けず、edits 配列で1回にまとめてください。同じ編集が3回連続で拒否された場合は、作業を止めてユーザーに相談してください。】」'

sentence='これから実行されようとしているファイル書き込みイベント（PreToolUse）: $ARGUMENTS

この書き込みを実行してよいか、文章スタイル（文レベル）の観点で事前に検証する。書き込み予定の内容は tool_input に入っている（Write は content、Edit は new_string または edits 配列の各 new_string）。手順:
1. tool_input.file_path の拡張子が .md / .txt 以外の場合、またはパスに CLAUDE.md・MEMORY.md・/.claude/ を含む場合は、検査対象外として許可する
2. 書き込み予定の内容だけを、末尾のルールに照らして検査する。ファイルの Read は行わない。文書全体との整合（重複・接続・構成）は別の検証が担当するため、ここでは判定しない
3. 違反が1件以上あれば書き込みを拒否（不合格）とし、理由には重大なものから最大3件まで「原文の引用・違反したルール・修正案（1行）」を列挙する。明白な違反がなければ、検討の経過を書かずに直ちに許可（合格）とする
4. '"$deny_tail"'

検査対象外: コードブロック（``` 内）、引用ブロック（> 行）、URL、脚注定義、mermaid 図のソース、JSON などのコード片。見出しの体言止めは違反にしない。書き込み箇所の外にもともとある違反は指摘しない。

=== 文章スタイルルール ===
'

context='これから実行されようとしているファイル書き込みイベント（PreToolUse）: $ARGUMENTS

この書き込みを実行してよいか、文書全体との文脈整合の観点で事前に検証する。文レベルの文法・語彙・文体は別の検証が担当するため、ここでは判定しない。書き込み予定の内容は tool_input に入っている（Write は content、Edit は new_string または edits 配列の各 new_string）。手順:
1. tool_input.file_path の拡張子が .md / .txt 以外の場合、またはパスに CLAUDE.md・MEMORY.md・/.claude/ を含む場合は、検査対象外として許可する
2. 文脈を把握する:
   - Edit で new_string が old_string から語句を削っただけの場合、または誤字・表記の修正だけの場合は、Read せず直ちに許可する（新しい主張が加わらないため）
   - Write の場合、tool_input.content が置き換え後の文書全体そのものなので、ファイルは Read せず content を文書全体として使う
   - Edit の場合、編集前の現行ファイルを読む。Read は最大1回とする。まず tool_input.file_path を Read し、全文が返れば（約2,000行以内）それを使う。長くて途中までしか読めない場合は、Grep（-n）で tool_input.old_string の先頭行を特定し、その行を中心とした約2,000行を1回だけ Read する（offset = 該当行 - 1000、limit = 2000。offset が負なら 0）
   - Edit 対象のファイルを読めない場合は、検査せず許可する（文レベルの検証は別で行われる）
3. 次の観点で検査する:
   - 書き込み箇所が直前・直後の段落と論理的に接続するか（唐突な話題転換・指示語の宙づりがないか）
   - 書き込み内容が、文書の他の箇所と重複しないか（同じ主張・説明の言い直しは冗長として不合格）。照合は書き込み箇所と同一セクション・隣接セクション・文書冒頭の結論部を重点とし、全文の網羅的な相互比較は行わない
   - 書き込み内容が、置かれるセクションのトピックから外れないか
   - Write の場合はさらに文書の構成を検査する: 結論・全体像が冒頭に置かれているか（ピラミッド原則）、1つのセクションに複数のトピックが混在していないか
4. 違反が1件以上あれば書き込みを拒否（不合格）とし、理由には重大なものから最大3件まで「原文の引用・問題点・修正案（1行）」を列挙する。明白な違反がなければ、検討の経過を書かずに直ちに許可（合格）とする
5. '"$deny_tail"'

検査対象外: コードブロック（``` 内）、引用ブロック（> 行）、URL、脚注定義、mermaid 図のソース、JSON などのコード片。'

jq -n --arg sp "${sentence}${rules}" --arg cp "$context" '
def entry($if; $prompt; $msg): {
  "type": "agent",
  "if": $if,
  "prompt": $prompt,
  "model": "claude-sonnet-5",
  "timeout": 150,
  "statusMessage": $msg
};
{
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
          entry("Write(**/*.md)"; $sp; "文体を書き込み前に検証中"),
          entry("Write(**/*.txt)"; $sp; "文体を書き込み前に検証中"),
          entry("Edit(**/*.md)"; $sp; "文体を書き込み前に検証中"),
          entry("Edit(**/*.txt)"; $sp; "文体を書き込み前に検証中"),
          entry("Write(**/*.md)"; $cp; "文脈を書き込み前に検証中"),
          entry("Write(**/*.txt)"; $cp; "文脈を書き込み前に検証中"),
          entry("Edit(**/*.md)"; $cp; "文脈を書き込み前に検証中"),
          entry("Edit(**/*.txt)"; $cp; "文脈を書き込み前に検証中")
        ]
      }
    ]
  }
}' > "$plugin/hooks/hooks.json"

echo "生成完了: $plugin/hooks/hooks.json"
