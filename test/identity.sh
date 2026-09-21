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

# ---------- 0. cwd 编码必须与 Claude Code 的真实目录命名一致(逐字符规则) ----------
# 这些对照值取自真实会话:Claude 在 Windows 上把 `D:\ai-project` 建成的项目目录就叫
# `D--ai-project`(非压连续段的 `-D-ai-project`)。
enc(){ eq "$(cwd_encode "$1")" "$2" "$3"; }
enc "/home/fengye"        "-home-fengye"      "enc: POSIX 根(单分隔)"
enc "D:\\ai-project"       "D--ai-project"     "enc: Windows 盘根(逐字符,双 '-' 关键)"
enc "C:\\Users\\EDY"       "C--Users-EDY"      "enc: Windows 用户根"
enc "/mnt/d/ai-project"    "-mnt-d-ai-project" "enc: WSL 挂载路径"
enc "/home/alen/code/foo"  "-home-alen-code-foo" "enc: 子目录"

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

# ---------- 6. cwd 改写必须是「字节级」,不得破坏 UTF-8(回归:曾用 perl -CS 双重编码) ----------
ENCSIM="$SIM/enc"; mkdir -p "$ENCSIM"
# 注意:这里用 printf %b + shell \x,\xe8\xb4\xa2 等才是字面多字节字节;写一个带中文/价格符的 jsonl
printf '%s\n' '{"type":"user","cwd":"/orig/É财重data/载","text":"中文 重载 价格 price é ☂ ✓"}' > "$ENCSIM/in.jsonl"
ENCIN_BYTES="$(cat "$ENCSIM/in.jsonl")"
cwd_rewrite_copy "$ENCSIM/in.jsonl" "$ENCSIM/out.jsonl" "/orig/É财重data/载" "/local/twin/载字" 2>/dev/null
ENCOUT_BYTES="$(cat "$ENCSIM/out.jsonl")"
# cwd 前缀应被改写
ENCOUT_BYTES="$(cat "$ENCSIM/out.jsonl")"
if [[ "$ENCOUT_BYTES" == *'"cwd":"/local/twin'* ]]; then
  ok "cwd 改写:cwd 前缀已换成本机路径"
else
  bad "cwd 改写失败,前缀未替换"; echo "    got:  ${ENCOUT_BYTES}"
fi
# 不得出现双重编码「Ã©」(原始字节 \xC3\x83\xC2\xA9)。用 perl 按字节计数,免 grep -P 可移植问题。
ENCMB="$(printf '%s' "$ENCOUT_BYTES" | perl -e 'local $/; my $d=<>; my $c=0; $c++ while $d =~ /\xC3\x83\xC2\xA9/g; print $c')"
[ "${ENCMB:-0}" -eq 0 ] && ok "UTF-8 不被破坏:无双重编码 Ã©" || bad "UTF-8 被双重编码(找到 ${ENCMB} 处)"
# 逐字节一致性:把输入里的源前缀整体换成目标前缀后,应等于输出(证明除 cwd 外正文原样保留)
ENCFIXED="$(printf '%s' "$ENCIN_BYTES" | sed "s#/orig/É财重data/载#/local/twin/载字#g")"
if [ "$ENCFIXED" = "$ENCOUT_BYTES" ]; then
  ok "字节级一致:除 cwd 前缀外原文完整保留"
else
  bad "非字节级改写,正文被改动"
fi

rm -rf "$SIM/enc"

# ---------- 7. 防御性中和残破工具调用块(强杀中断遗留,否则 --resume 400) ----------
SANSIM="$SIM/san"; mkdir -p "$SANSIM"
cat > "$SANSIM/broken.jsonl" <<'EOF'
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"早上好"}],"model":"claude-sonnet-5"},"timestamp":"2026-01-01T00:00:00Z"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"","name":"","input":{"cmd":"ls"}}],"model":"claude-sonnet-5"},"timestamp":"2026-01-01T00:00:01Z"}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"","content":"-rw-r--r--"}],"model":"claude-sonnet-5"},"timestamp":"2026-01-01T00:00:02Z"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"完成 重载 é ✓"}],"model":"claude-sonnet-5"},"timestamp":"2026-01-01T00:00:03Z"}
EOF
cp -f "$SANSIM/broken.jsonl" "$SANSIM/expect.jsonl"
sanitize_broken_toolcalls "$SANSIM/broken.jsonl"
SANO="$(cat "$SANSIM/broken.jsonl")"
# 中和后不应再有空引用块
if [[ "$SANO" != *'"type":"tool_use","id":"","name":""'* ]] && [[ "$SANO" != *'"tool_use_id":""'* ]]; then
  ok "中和后无残留空 tool_use / 空 tool_use_id tool_result"
else
  bad "残破块未中和"; echo "    got:  ${SANO}"
fi
# 所有行仍是合法 JSON 且 UTF-8 不破坏(逐行用 perl JSON 校验 + 检查双重编码)
SANJSON="$(printf '%s' "$SANO" | perl -MJSON::PP -e 'use JSON::PP; local $/; my $d=<>; my $bad=0; for my $l (split/\n/,$d){ next if $l eq ""; eval { JSON::PP->new->utf8(1)->decode($l) } or do { $bad++; last } }; print $bad' 2>/dev/null)"
[ "$SANJSON" = "0" ] && ok "中和后每行仍为合法 JSON" || bad "中和破坏 JSON 结构(非法行数=$SANJSON)"
SANMB="$(printf '%s' "$SANO" | perl -e 'local $/; my $d=<>; my $c=0; $c++ while $d =~ /\xC3\x83\xC2\xA9/g; print $c')"
[ "${SANMB:-0}" -eq 0 ] && ok "中和保留 UTF-8:无双重编码 Ã©" || bad "中和破坏 UTF-8(找到 ${SANMB} 处)"
# 无残破块的文件应被整体原样跳过(字节级不变)
cat > "$SANSIM/clean.jsonl" <<'EOF'
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"纯文本 中文 ✓"}],"model":"claude-sonnet-5"},"timestamp":"2026-01-01T00:00:00Z"}
EOF
CLEAN_BEFORE="$(cat "$SANSIM/clean.jsonl")"
sanitize_broken_toolcalls "$SANSIM/clean.jsonl"
CLEAN_AFTER="$(cat "$SANSIM/clean.jsonl")"
[ "$CLEAN_BEFORE" = "$CLEAN_AFTER" ] && ok "纯文本行逐字节原样保留" || bad "纯文本行被改动"
rm -rf "$SANSIM"

echo
echo "── 结果: PASS=${PASS} FAIL=${FAIL} ──"
[ "${FAIL}" -eq 0 ] || exit 1
echo "ALL PASSED"