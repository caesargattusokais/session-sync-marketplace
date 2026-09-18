#!/usr/bin/env bash
# 导入共享会话并自动归位(A 模式)。
# 归位优先级: ①本机已有同编码目录 ②ROOT_MAP ③$HOME 猜(无规则时) ④_unclaimed。
# 特性: pull 冲突自愈、来源(host)展示、待认领给出补规则建议。
set -uo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${PLUGIN_DIR}/config.sh"
source "${PLUGIN_DIR}/gitutil.sh"
source "${PLUGIN_DIR}/pathcode.sh"

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
  local code="$1"
  if [ -d "${SESSION_HOME}/${code}" ]; then echo "${code}"; return; fi
  local r hit
  for r in "${!ROOT_MAP[@]}"; do
    if hit="$(map_code "${code}" "${r}" "${ROOT_MAP[${r}]}")"; then echo "${hit}"; return; fi
  done
  if [ "${#ROOT_MAP[@]}" -eq 0 ]; then
    if hit="$(map_code "${code}" "${HOME}" "${HOME}")"; then echo "${hit}"; return; fi
  fi
  echo ""
}

gitutil_pull

[ -d "${SHARE_ROOT}/sessions" ] || { echo "[session-sync] 共享仓库里还没有 sessions/,跳过"; exit 0; }

restored=0; unclaimed=0
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

  target="$(target_code_of "${code}")"
  if [ -n "${target}" ]; then
    dest="${SESSION_HOME}/${target}"
  else
    dest="${SESSION_HOME}/_unclaimed/${code}"
    unclaimed=$(( unclaimed + 1 ))
    echo "[session-sync] (待认领) ${code}${src_host:+ (来自 ${src_host})} -> ${dest}"
  fi
  mkdir -p "${dest}"
  before="$(ls "${dest}"/*.jsonl 2>/dev/null | wc -l)"
  cp -f "${src}"/*.jsonl "${dest}/"
  after="$(ls "${dest}"/*.jsonl 2>/dev/null | wc -l)"
  echo "[session-sync] 导入 ${code} -> ${dest}  (新增 $(( after - before )) 份${src_host:+ | 来源 ${src_host}})"
  restored=$(( restored + 1 ))
done

echo "[session-sync] 导入完成:处理 ${restored} 个会话目录"
if [ "${unclaimed}" -gt 0 ]; then
  echo
  echo "  ⚠ ${unclaimed} 个目录未能自动归位(两端根路径不同)。"
  echo "    补一条 ROOT_MAP 后重新 pull 即可自动放入,最简单是在交互里填:"
  echo "      带 -t 终端运行 setup.sh,或在 settings.sh 加:"
  echo "        declare -A ROOT_MAP=( [\"/远端根\"]=\"/本机根\" )"
fi
echo "[session-sync] 用 claude --resume (或重启会话) 即可继续别机的对话"