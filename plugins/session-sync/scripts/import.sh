#!/usr/bin/env bash
# 导入共享会话并自动归位。
# 归位优先级: ①本机已有同编码目录 ②ROOT_MAP(显式) ③项目身份(自动) ④$HOME 同根 ⑤_unclaimed。
# 项目身份命中时,把会话 cwd 前缀改写成本机 checkout 路径,续聊即回到本地目录。
# 特性: pull 冲突自愈、来源(host)展示、--rescan 强制重建本机 checkit 索引。
set -uo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${PLUGIN_DIR}/config.sh"
source "${PLUGIN_DIR}/lock.sh"
source "${PLUGIN_DIR}/gitutil.sh"
source "${PLUGIN_DIR}/pathcode.sh"
source "${PLUGIN_DIR}/identity.sh"

FORCE_RESCAN=0
[ "${1:-}" = "--rescan" ] && FORCE_RESCAN=1

acquire_lock || exit 0
ensure_identity_cache "${FORCE_RESCAN}"

# 用一条「根=源前缀」规则映射编码到目标机路径;命中返回 0
map_code() {
  local code="$1" src="$2" dst="$3"
  local renc rel suffix
  renc="$(cwd_encode "${src}")"
  if [ "${code}" = "${renc}" ]; then
    cwd_encode "${dst}"; return 0
  fi
  if [[ "${code}" == "${renc}-"* ]]; then
    suffix="${code#"${renc}"}"
    rel="$(cwd_decode_suffix "${suffix}")"
    cwd_encode "${dst}/${rel}"; return 0
  fi
  return 1
}

target_code_of() {
  local code="$1" sdir="$2"
  if [ -d "${SESSION_HOME}/${code}" ]; then echo "${code}"; return; fi
  local r hit
  for r in "${!ROOT_MAP[@]}"; do
    if hit="$(map_code "${code}" "${r}" "${ROOT_MAP[${r}]}")"; then echo "${hit}"; return; fi
  done
  if [ -n "$(identity_remote_of "${sdir}")" ]; then
    if hit="$(resolve_by_identity "${sdir}")"; then echo "${hit}"; return; fi
  fi
  if [ "${#ROOT_MAP[@]}" -eq 0 ]; then
    if hit="$(map_code "${code}" "${HOME}" "${HOME}")"; then echo "${hit}"; return; fi
  fi
  echo ""
}

gitutil_pull

[ -d "${SHARE_ROOT}/sessions" ] || { echo "[session-sync] 共享仓库里还没有 sessions/,跳过"; exit 0; }

restored=0; unclaimed=0; identity_placed=0
for src in "${SHARE_ROOT}"/sessions/*/; do
  [ -d "${src}" ] || continue
  code="$(basename "${src}")"
  ls "${src}"/*.jsonl >/dev/null 2>&1 || continue

  # 展示来源
  src_host=""
  if [ -f "${src}/.source" ]; then
    # shellcheck disable=SC1090
    while IFS= read -r kv; do [ "${kv#host=}" != "${kv}" ] && src_host="${kv#host=}"; done < "${src}/.source"
  fi

  target="$(target_code_of "${code}" "${src}")"
  if [ -n "${target}" ]; then
    dest="${SESSION_HOME}/${target}"
  else
    dest="${SESSION_HOME}/_unclaimed/${code}"
    unclaimed=$(( unclaimed + 1 ))
    echo "[session-sync] (待认领) ${code}${src_host:+ (来自 ${src_host})} -> ${dest}"
  fi
  mkdir -p "${dest}"
  before="$(ls "${dest}"/*.jsonl 2>/dev/null | wc -l)"

  # 项目身份:cwd 改写(prefix origin_toplevel -> 本机 checkout 路径),仅命中身份时
  ipath="" itl=""
  remote="$(identity_remote_of "${src}")"
  if [ -n "${remote}" ]; then ipath="${IDENT_CACHE[$remote]:-}"; itl="$(identity_toplevel_of "${src}")"; fi
  do_rewrite=0
  if [ -n "${ipath}" ] && [ -n "${itl}" ] && [ "${itl}" != "${ipath}" ] \
     && [ "${target}" = "$(cwd_encode "${ipath}")" ]; then
    do_rewrite=1
  fi

  if [ "${do_rewrite}" = "1" ]; then
    for f in "${src}"/*.jsonl; do [ -e "${f}" ] || continue; cwd_rewrite_copy "${f}" "${dest}/$(basename "${f}")" "${itl}" "${ipath}"; done
    identity_placed=$(( identity_placed + 1 ))
  else
    for f in "${src}"/*.jsonl; do [ -e "${f}" ] || continue; cp -f "${f}" "${dest}/"; done
  fi

  after="$(ls "${dest}"/*.jsonl 2>/dev/null | wc -l)"
  extra=""
  [ "${do_rewrite}" = "1" ] && extra=" | cwd->${ipath}"
  echo "[session-sync] 导入 ${code} -> ${dest}  (新增 $(( after - before )) 份${src_host:+ | 来源 ${src_host}}${extra})"
  restored=$(( restored + 1 ))
done

echo "[session-sync] 导入完成:处理 ${restored} 个会话目录(其中身份归位 ${identity_placed})"
if [ "${unclaimed}" -gt 0 ]; then
  echo
  echo "  ⚠ ${unclaimed} 个目录未能自动归位。"
  echo "    · 这些项目在共享仓里带 git 身份,但本机没找到同名 checkout。"
  echo "      在本机 clone 对应仓库(任意路径)后重跑 pull --rescan 即自动归位。"
  echo "    · 或显式给一条根替换(优先于自动): setup.sh 里声明 -A ROOT_MAP=( [\"/远端根\"]=\"/本机根\" )。"
fi
echo "[session-sync] 用 claude --resume (或重启会话) 即可继续别机的对话"