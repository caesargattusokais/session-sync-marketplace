#!/usr/bin/env bash
# =====================================================================
# session-sync「超大会话分片存储」回归测试。
# 共享仓走 git(+GitHub),单文件有 100MB 硬限;超 SHARD_MAX 的会话被切成
# part_* 分片存储,导入按序拼回。覆盖:export 切分、import 拼接逐字节一致、
# 源未变不重切(去重)。
# 用法: bash test/shard.sh   (不碰真实 ~/.claude)
# =====================================================================
set -uo pipefail

PLUGIN="${SESSION_SYNC_PLUGIN:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../plugins/session-sync" && pwd)}"
S="$(cd "${PLUGIN}" && pwd)"

SIM="$(mktemp -d)"; trap 'rm -rf "$SIM"' EXIT
PASS=0; FAIL=0
ok(){  echo "  ✓ $1"; PASS=$((PASS+1)); }
bad(){ echo "  ✗ FAIL: $1"; FAIL=$((FAIL+1)); }

SESH="abc123"
SRC_HOME="$SIM/srchome"; IMP_HOME="$SIM/importhome"; SHARE="$SIM/share"
SRC_DIR="$SRC_HOME/-demo"
mkdir -p "$SRC_DIR" "$IMP_HOME"
# 造一条 >SHARD_MAX(测试里 1000B 强制切多片)的会话
{ for i in $(seq 1 20); do printf '{"type":"user","cwd":"/home/fengye","request":"line %05d %200s"}\n' "$i" "xxxxxxxxxxxxxxxx"; done; } > "$SRC_DIR/$SESH.jsonl"

mkdir -p "$SHARE"; (cd "$SHARE" && git init -q . && git -c user.name=t -c user.email=t@l commit --allow-empty -qm init)

writeconf(){ # <file> <session_home> <host>
  printf 'SESSION_HOME="%s"\nSHARE_ROOT="%s"\nSANITIZE=0\nIDENTITY_SCAN_DEPTH=1\nIDENTITY_CACHE_FILE="%s"\nSHARD_MAX=1000\nDEBUG_HOST=%s\n' \
    "$1" "$SHARE" "$SIM/ic_$3" "$3" > "$2"
}
writeconf "$SRC_HOME" "$SIM/confA" A
writeconf "$IMP_HOME" "$SIM/confB" B

# ---------- 1. export 把超大会话切成 part_* 分片,并写 .shard ----------
SESSION_SYNC_CONF="$SIM/confA" bash "$S/scripts/export.sh" >/dev/null 2>&1
SDIR="$SHARE/sessions/-demo/$SESH"
[ -d "$SDIR" ] && parts=$(ls "$SDIR"/part_* 2>/dev/null | wc -l) || parts=0
[ "$parts" -ge 2 ] && ok "export 切成 ≥2 分片(共 ${parts} 片)" || bad "预期分片,实际 parts=$parts"
[ -f "$SDIR/.shard" ] && ok ".shard manifest 已写" || bad ".shard 缺失"
[ -e "$SHARE/sessions/-demo/$SESH.jsonl" ] && bad "顶层不应再有单文件" || ok "顶层无残留单文件"

# ---------- 2. import 逐字节拼回 ----------
SESSION_SYNC_CONF="$SIM/confB" bash "$S/scripts/import.sh" >/dev/null 2>&1
if cmp -s "$SRC_DIR/$SESH.jsonl" "$IMP_HOME/-demo/$SESH.jsonl"; then
  ok "import 拼回与源逐字节一致"
else
  bad "拼回不一致 (src=$(wc -c <"$SRC_DIR/$SESH.jsonl")B got=$(wc -c <"$IMP_HOME/-demo/$SESH.jsonl" 2>/dev/null || echo NA )B)"
fi

# ---------- 3. 源未变再 export → 不重切(.shard 的 src_sha 命中) ----------
b_mtime=$(stat -c %Y "$SDIR/.shard" 2>/dev/null)
SESSION_SYNC_CONF="$SIM/confA" bash "$S/scripts/export.sh" >/dev/null 2>&1
a_mtime=$(stat -c %Y "$SDIR/.shard" 2>/dev/null)
[ "$b_mtime" = "$a_mtime" ] && ok "源未变不重切(sha 命中,零 churn)" || bad "源未变却重切了"

# ---------- 4. 小会话仍走原单文件路径(分片不误伤) ----------
printf '{"type":"user","cwd":"/home/fengye","request":"small"}\n' > "$SRC_HOME/-demo/small.jsonl"
SESSION_SYNC_CONF="$SIM/confA" bash "$S/scripts/export.sh" >/dev/null 2>&1
[ -f "$SHARE/sessions/-demo/small.jsonl" ] && ok "小会话仍是单文件路径" || bad "小会话被误分片"

echo "── 结果: PASS=${PASS} FAIL=${FAIL} ──"
[ "${FAIL}" -eq 0 ] && echo "ALL PASSED" || exit 1