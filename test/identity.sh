#!/usr/bin/env bash
# =====================================================================
# session-sync「项目身份」归位回归测试(A 模式零配置核心)。
# 覆盖:remote 规范化、身份重归位 + cwd 改写、ROOT_MAP 优先级、
#       无本地 checkout 落 _unclaimed 不丢、scan 深度与 node_modules 剪枝。
# 可在任意机器/CI 运行,不碰真实 ~/.claude。
# 用法: bash test/identity.sh
# =====================================================================
set -uo pipefail

PLUGIN="${SESSION_SYNC_PLUGIN:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../plugins/session-sync" && pwd)}"
S="$(cd "${PLUGIN}" && pwd)"

SIM="$(mktemp -d)"; trap 'rm -rf "$SIM"' EXIT
PASS=0; FAIL=0
ok(){  echo "  ✓ $1"; PASS=$((PASS+1)); }
bad(){ echo "  ✗ FAIL: $1"; FAIL=$((FAIL+1)); }
eq(){ [ "$1" = "$2" ] && ok "$3" || { bad "$3"; echo "      got:    [$1]"; echo "      wanted: [$2]"; }; }

# 单测函数直接 source(不走 import/export,避免依赖完整仓库)
source "${S}/scripts/config.sh"
source "${S}/scripts/pathcode.sh"
source "${S}/scripts/identity.sh"

# ---------- 1. remote 规范化 ----------
eq "$(git_canonical_remote 'git@github.com:Acme/Widget.git')" "github.com/acme/widget" "canon: scp git@ + .git"
eq "$(git_canonical_remote 'https://github.com/Acme/widget/')" "github.com/acme/widget" "canon: https + 尾部斜杠"
eq "$(git_canonical_remote 'ssh://git@github.com:2222/acme/widget.git')" "github.com/acme/widget" "canon: ssh + 端口"
eq "$(git_canonical_remote 'https://GITHUB.COM/Acme/Widget.git')" "github.com/acme/widget" "canon: 大小写归一(host 大写)"

# ---------- 准备共享仓(带 .identity 的合作会话) ----------
SHARE="$SIM/share"; mkdir -p "$SHARE/sessions"; git init -q "$SHARE"
(cd "$SHARE" && git -c user.name=t -c user.email=t@l commit --allow-empty -qm init)
FRG="/remote/orig/project"                      # 远端 origin 的仓库根(会话里真实存在的 cwd 前缀)
RLOC="$SIM/trg/proj/foo"                        # 本机对应 checkout
SC="$(cwd_encode "${FRG}")"
mkdir -p "$SHARE/sessions/${SC}"
printf 'remote=github.com/acme/widget\ntoplevel=%s\n' "${FRG}" > "$SHARE/sessions/${SC}/.identity"
printf '{"type":"user","cwd":"%s/sub/dir"}\n' "${FRG}" > "$SHARE/sessions/${SC}/s1.jsonl"

# 本机 checkout 的 .git/config(scan 只读该文件,无需真实 git init)
mkdir -p "${RLOC}/.git"
printf '[core]\n\tbare = false\n[remote "origin"]\n\turl = https://github.com/Acme/Widget.git\n\tfetch = +refs/heads/*:refs/remotes/origin/*\n' > "${RLOC}/.git/config"

mkconf(){
  # <file> [额外KEY]=[VALUE]...:写一份可再生 import 配置(extra 类似 KEY=VALUE,可多次)
  local f="$1"; shift
  printf 'SESSION_HOME="%s"\nSHARE_ROOT="%s"\nSANITIZE=0\nIDENTITY_ROOTS="%s"\nIDENTITY_SCAN_DEPTH=3\nIDENTITY_CACHE_FILE="%s"\n' \
    "${SIM}/home" "$SHARE" "$SIM/trg" "$SIM/icache" > "$f"
  for kv in "$@"; do printf '%s\n' "${kv}" >> "$f"; done
}

# ---------- 2. 身份重归位 + cwd 改写 ----------
mkconf "$SIM/conf.a"
SESSION_SYNC_CONF="$SIM/conf.a" bash "$S/scripts/import.sh" >/dev/null 2>&1
RIC="$(cwd_encode "${RLOC}")"
fh(){ [ -f "${1}" ] && ok "$2" || bad "$2"; }
fh "$SIM/home/${RIC}/s1.jsonl" "身份重归位:落到本机 checkout 编码目录"
if [ -f "$SIM/home/${RIC}/s1.jsonl" ]; then
  if grep -qF "\"cwd\":\"${RLOC}/sub/dir\"" "$SIM/home/${RIC}/s1.jsonl"; then
    ok "cwd 前缀已改写成当地路径"
  else
    bad "cwd 改写失败"; echo "    got:  $(grep -o '('"cwd"':[^}]*' "$SIM/home/${RIC}/s1.jsonl" | head -1)"
  fi
fi

# ---------- 3. ROOT_MAP 优先级(显式 > 身份) ----------
rm -f "$SIM/icache"
mkconf "$SIM/conf.b" "declare -A ROOT_MAP=( [\"${FRG}\"]=\"${SIM}/rtg\" )"
SESSION_SYNC_CONF="$SIM/conf.b" bash "$S/scripts/import.sh" >/dev/null 2>&1
RIC2="$(cwd_encode "$SIM/rtg")"
fh "$SIM/home/${RIC2}/s1.jsonl" "ROOT_MAP 优先于身份归位"

# ---------- 4. 无本地 checkout → 落 _unclaimed 不丢 ----------
SC2="$(cwd_encode "/elsewhere/nope")"
mkdir -p "$SHARE/sessions/${SC2}"
printf 'remote=gitlab.com/some/other\ntoplevel=/elsewhere/nope\n' > "$SHARE/sessions/${SC2}/.identity"
printf '{"type":"user","cwd":"/elsewhere/nope"}\n' > "$SHARE/sessions/${SC2}/lost.jsonl"
SESSION_SYNC_CONF="$SIM/conf.a" bash "$S/scripts/import.sh" >/dev/null 2>&1
fh "$SIM/home/_unclaimed/${SC2}/lost.jsonl" "无本地 checkout → 落 _unclaimed 不丢"

# ---------- 5. scan 深度 + node_modules 剪枝 ----------
mkdir -p "$SIM/trg/simple/.git"
printf '[remote "origin"]\n\turl = https://github.com/deep/Simple.git\n' > "$SIM/trg/simple/.git/config"
mkdir -p "$SIM/trg/app/node_modules/pkg/deep/.git"
printf '[remote "origin"]\n\turl = https://github.com/hidden/Mod.git\n' > "$SIM/trg/app/node_modules/pkg/deep/.git/config"
IDENT_CACHE=()
IDENTITY_ROOTS="$SIM/trg"; IDENTITY_CACHE_FILE="$SIM/icache2"; IDENTITY_SCAN_DEPTH=3
ensure_identity_cache 1 >/dev/null 2>&1   # 强制重建
[ -n "${IDENT_CACHE[github.com/deep/simple]:-}" ] && ok "scan 命中普通仓库" || bad "scan 漏掉普通仓库"
[ -z "${IDENT_CACHE[github.com/hidden/mod]:-}" ] && ok "node_modules 被剪枝(不进入)" || bad "node_modules 未剪枝"

echo
echo "── 结果: PASS=${PASS} FAIL=${FAIL} ──"
[ "${FAIL}" -eq 0 ] || exit 1
echo "ALL PASSED"