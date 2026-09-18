#!/usr/bin/env bash
# =====================================================================
# session-sync 端到端回归测试(可在任意机器/CI 运行,不碰真实 ~/.claude)。
# 覆盖:整包导出、全新机零配置归位($HOME 根)、ROOT_MAP 精确+子目录、
#       未命中进 _unclaimed 不丢、脱敏(SANITIZE)、来源 host 标记。
# 用法: bash test/e2e.sh   (任一步失败以非零退出)
# =====================================================================
set -uo pipefail

PLUGIN="${SESSION_SYNC_PLUGIN:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../plugins/session-sync" && pwd)}"
S="$(cd "${PLUGIN}" && pwd)"
source "${S}/scripts/pathcode.sh"

SIM="$(mktemp -d)"; trap 'rm -rf "$SIM"' EXIT
PASS=0; FAIL=0
ok(){  echo "  ✓ $1"; PASS=$((PASS+1)); }
bad(){ echo "  ✗ FAIL: $1"; FAIL=$((FAIL+1)); }
fh(){ [ -f "${1:-}" ] && ok "$2" || bad "$2"; }

SHARE="$SIM/share"; git init -q "$SHARE"
(cd "$SHARE" && git -c user.name=t -c user.email=t@l commit --allow-empty -qm init)

HENC="$(cwd_encode "$HOME")"
mkdir -p "$SHARE/sessions/$HENC"
mkdir -p "$SHARE/sessions/$(cwd_encode /home/alen)"
mkdir -p "$SHARE/sessions/$(cwd_encode /home/alen/code/foo)"
echo '{"type":"last-prompt","sessionId":"home1"}' > "$SHARE/sessions/$HENC/home1.jsonl"
echo '{"type":"last-prompt","sessionId":"a1"}' > "$SHARE/sessions/$(cwd_encode /home/alen)/a1.jsonl"
echo '{"type":"last-prompt","sessionId":"a2"}' > "$SHARE/sessions/$(cwd_encode /home/alen/code/foo)/a2.jsonl"
printf 'host=fakemachine date=2026-01-01T00:00:00+00:00 sanitize=yes\n' > "$SHARE/sessions/$(cwd_encode /home/alen)/.source"

export SESSION_SYNC_CONF=""
run(){ SESSION_SYNC_CONF="$1" bash "$S/$2" "${@:3}" >/dev/null 2>&1; }

# 场景1: 全新机 + 空 ROOT_MAP → $HOME 根零配置归位;不同根进 unclaimed
conf="$SIM/b0"; printf 'SESSION_HOME="%s"\nSHARE_ROOT="%s"\nSANITIZE=0\ndeclare -A ROOT_MAP=()\n' "$SIM/b0h" "$SHARE" > "$conf"
run "$conf" scripts/import.sh
fh "$SIM/b0h/$HENC/home1.jsonl" "全新机零配置归位(\$HOME 根)"
fh "$SIM/b0h/_unclaimed/$(cwd_encode /home/alen)/a1.jsonl" "不同根候补 _unclaimed(a1)"
fh "$SIM/b0h/_unclaimed/$(cwd_encode /home/alen/code/foo)/a2.jsonl" "不同根子目录 _unclaimed(a2)"

# 场景2: ROOT_MAP 精确 + 子目录
conf="$SIM/b1"; printf 'SESSION_HOME="%s"\nSHARE_ROOT="%s"\nSANITIZE=0\ndeclare -A ROOT_MAP=( ["/home/alen"]="/workspace/x" )\n' "$SIM/b1h" "$SHARE" > "$conf"
run "$conf" scripts/import.sh
fh "$SIM/b1h/$(cwd_encode /workspace/x)/a1.jsonl" "ROOT_MAP 根映射"
fh "$SIM/b1h/$(cwd_encode /workspace/x/code/foo)/a2.jsonl" "ROOT_MAP 子目录映射"

# 场景3: 脱敏仅作用于导出副本,源不动 + 来源 host 标记
sofar="$SIM/b2src"; lsrc="$sofar/$(cwd_encode "$HOME")"; mkdir -p "$lsrc"
echo '{"toolUse":{"name":"Bash"}} in: ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 rest' > "$lsrc/sec.jsonl"
conf="$SIM/b2"; printf 'SESSION_HOME="%s"\nSHARE_ROOT="%s"\nSANITIZE=1\ndeclare -A ROOT_MAP=()\n' "$sofar" "$SHARE" > "$conf"
run "$conf" scripts/export.sh
shared_copy="$SHARE/sessions/$(cwd_encode "$HOME")/sec.jsonl"
if [ -f "$shared_copy" ] && grep -q 'REDACTED' "$shared_copy" && ! grep -q 'ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ' "$shared_copy"; then
  ok "导出副本已脱敏(不含原文)"
else
  bad "导出副本脱敏失败"
fi
grep -q 'ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ' "$lsrc/sec.jsonl" && ok "本机源文件未被改动" || bad "源文件被改动!"
fh "$SHARE/sessions/$(cwd_encode "$HOME")/.source" "已写入来源 host 标记(.source)"

echo
echo "── 结果: PASS=${PASS} FAIL=${FAIL} ──"
[ "${FAIL}" -eq 0 ] || exit 1
echo "ALL PASSED"