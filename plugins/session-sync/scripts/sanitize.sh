#!/usr/bin/env bash
# =====================================================================
# 会话脱敏工具。会话文件里常藏有 GitHub PAT / OpenAI key / AWS / Slack /
# 各种 password / secret / api_token。导入共享仓库前把明显的密钥替换成
# 占位符,保留对话上下文但去掉真实凭据,降低泄露面。
#
# 仅对「导出的副本」生效 —— 绝不动源目录 ~/.claude/projects 下的原文件。
# 没有 perl 的环境则原样复制(SANITIZE 无法生效),见 config.sh SANITIZE。
# =====================================================================

# <in> <out>: 读入一份 jsonl,写出脱敏后的副本
sanitize_file() {
  local in="$1" out="$2"
  if command -v perl >/dev/null 2>&1; then
    local ps
    ps="$(cat <<'PL'
s{gh[opsru]_[A-Za-z0-9]{20,}}{<REDACTED:TOKEN>}g;
s{sk-[A-Za-z0-9]{20,}}{<REDACTED:KEY>}g;
s{AKIA[0-9A-Z]{16}}{<REDACTED:AWS>}g;
s{xox[baprs]-[A-Za-z0-9]{6,}}{<REDACTED:SLACK>}g;
s{(?i:Bearer)\s+[A-Za-z0-9._\-+/=]{16,}}{<REDACTED:BEARER>}g;
s{(?i:(password|passwd|secret|api[_-]?key|token|auth))["\x27:\s]*[:=]["\x27:\s]*[A-Za-z0-9_\-+/]{12,}}{$1=<REDACTED:VALUE>}g;
PL
)"
    perl -CS -pe "$ps" "$in" > "$out.$$" 2>/dev/null && mv "$out.$$" "$out" || { rm -f "$out.$$"; cp -f "$in" "$out"; }
  else
    cp -f "$in" "$out"
  fi
}