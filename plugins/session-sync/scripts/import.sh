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

restored=0; unclaimed=0; unclaimed_noid=0; identity_placed=0
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
    [ -f "${src}/.identity" ] && : || unclaimed_noid=$(( unclaimed_noid + 1 ))
    echo "[session-sync] (待认领) ${code}${src_host:+ (来自 ${src_host})} -> ${dest}"
  fi
  mkdir -p "${dest}"
  before="$(ls "${dest}"/*.jsonl 2>/dev/null | wc -l)"

  # 是否通过 ROOT_MAP 归位;若是,记下 源根 -> 本机根 用于 cwd 前缀改写
  rmap_from="" rmap_to=""
  for r in "${!ROOT_MAP[@]}"; do
    if map_code "${code}" "${r}" "${ROOT_MAP[${r}]}" >/dev/null 2>&1; then
      rmap_from="${r}"; rmap_to="${ROOT_MAP[${r}]}"; break
    fi
  done

  # cwd 改写目标(prefix 远端根 -> 本机根),身份优先,ROOT_MAP 兜底:
  ipath="" itl=""
  remote="$(identity_remote_of "${src}")"
  if [ -n "${remote}" ]; then ipath="${IDENT_CACHE[$remote]:-}"; itl="$(identity_toplevel_of "${src}")"; fi
  do_rewrite=0
  if [ -n "${ipath}" ] && [ -n "${itl}" ] && [ "${itl}" != "${ipath}" ] \
     && [ "${target}" = "$(cwd_encode "${ipath}")" ]; then
    do_rewrite=1
  fi

  rw_from="" rw_to="" ; via=""
  if [ "${do_rewrite}" = "1" ]; then rw_from="${itl}"; rw_to="${ipath}"; via="identity";
  elif [ -n "${rmap_from}" ] && [ "${rmap_from}" != "${rmap_to}" ]; then rw_from="${rmap_from}"; rw_to="${rmap_to}"; via="ROOT_MAP"; fi

  if [ -n "${rw_from}" ] && [ -n "${rw_to}" ] && [ "${rw_from}" != "${rw_to}" ]; then
    for f in "${src}"/*.jsonl; do [ -e "${f}" ] || continue; cwd_rewrite_copy "${f}" "${dest}/$(basename "${f}")" "${rw_from}" "${rw_to}"; done
  else
    for f in "${src}"/*.jsonl; do [ -e "${f}" ] || continue; cp -f "${f}" "${dest}/"; done
  fi
  # 防御:来源机强杀中断会留「空 id 的 tool_use / 空 tool_use_id 的 tool_result」,
  # 落地后就地中和成 text,保证任何历史来源的会话重放都能被网关接受。
  for f in "${src}"/*.jsonl; do [ -e "${f}" ] || continue; sanitize_broken_toolcalls "${dest}/$(basename "${f}")"; done
  [ "${do_rewrite}" = "1" ] && identity_placed=$(( identity_placed + 1 ))

  after="$(ls "${dest}"/*.jsonl 2>/dev/null | wc -l)"
  extra=""
  [ -n "${via}" ] && extra=" | cwd->${rw_to}(${via})"
  echo "[session-sync] 导入 ${code} -> ${dest}  (新增 $(( after - before )) 份${src_host:+ | 来源 ${src_host}}${extra})"
  restored=$(( restored + 1 ))
done

echo "[session-sync] 导入完成:处理 ${restored} 个会话目录(其中身份归位 ${identity_placed})"
[ "${unclaimed}" -gt 0 ] && hasid=$(( unclaimed - unclaimed_noid )) || hasid=0
if [ "${unclaimed}" -gt 0 ]; then
  echo
  echo "  ⚠ ${unclaimed} 个目录未能自动归位。"
  if [ "${hasid}" -gt 0 ]; then
    echo "    · 带项目身份但没有本机同名 checkout:在本机 clone 对应仓库(任意路径)后重跑"
    echo "      pull --rescan 即自动归位。"
  fi
  if [ "${unclaimed_noid}" -gt 0 ]; then
    echo "    · 这些会话还没带项目身份(旧版导出、无 .identity):请在其来源机升到新版 plugin 并"
    echo "      push 一次,补上 .identity 后重跑 pull 即可按仓库身份自动归位。"
  fi
  echo "    · 或显式给一条根替换(优先于自动): setup.sh 里声明 -A ROOT_MAP=( [\"/远端根\"]=\"/本机根\" )。"
fi
echo "[session-sync] 用 claude --resume (或重启会话) 即可继续别机的对话"