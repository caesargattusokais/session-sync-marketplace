#!/usr/bin/env bash
# 导入共享会话(A 模式):从共享仓库 sessions/ 拉取,自动归位到本机对应项目。
#
# 归位逻辑(任一命中即止):
#   1. 本机已有同名 cwd 编码目录        -> 精确归位(两端绝对路径相同,零配置)
#   2. ROOT_MAP 规则匹配(含前缀替换)    -> 解码后按规则映射到本机路径
#   3. 都不命中                         -> 放入 _unclaimed/ 待认领,不丢、提示补规则
set -uo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${PLUGIN_DIR}/config.sh"
source "${PLUGIN_DIR}/pathcode.sh"

# 用一条「根=源前缀」规则映射编码到目标机路径;命中返回 0
map_code() {
  local code="$1" src="$2" dst="$3"
  local renc="${1:0:0}-${2:1}" rel suffix
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

# 由某共享编码 -> 本机应放置的目录名(空串表示无法归位,进待认领)
target_code_of() {
  local code="$1"
  # 规则1:本机已有同编码目录(两端绝对路径相同,且目录已在本机创建过)
  if [ -d "${SESSION_HOME}/${code}" ]; then echo "${code}"; return; fi

  # 规则2:用户在 settings 里显式配的根替换(优先级最高)
  local r hit
  for r in "${!ROOT_MAP[@]}"; do
    if hit="$(map_code "${code}" "${r}" "${ROOT_MAP[${r}]}")"; then echo "${hit}"; return; fi
  done

  # 规则3:没配规则时,若会话以本机 $HOME 为根(两端用户名/目录布局相同的零配置场景),
  #        直接把这条团导规则的 src 换成 $HOME 来猜归位——无歧义,不依赖目标机已有目录。
  if [ "${#ROOT_MAP[@]}" -eq 0 ]; then
    if hit="$(map_code "${code}" "${HOME}" "${HOME}")"; then echo "${hit}"; return; fi
  fi

  echo ""
}

# 先拉取远端共享仓库
if [ -d "${SHARE_ROOT}" ] && git -C "${SHARE_ROOT}" rev-parse --git-dir >/dev/null 2>&1; then
  git -C "${SHARE_ROOT}" pull --quiet 2>/dev/null \
    && echo "[session-sync] 已从共享仓库拉取" \
    || echo "[session-sync] (无 remote 或拉取失败,使用本地缓存)"
fi

[ -d "${SHARE_ROOT}/sessions" ] || { echo "[session-sync] 共享仓库里还没有 sessions/,跳过"; exit 0; }

restored=0; unclaimed=0
for src in "${SHARE_ROOT}"/sessions/*/; do
  [ -d "${src}" ] || continue
  code="$(basename "${src}")"
  ls "${src}"/*.jsonl >/dev/null 2>&1 || continue

  target="$(target_code_of "${code}")"
  if [ -n "${target}" ]; then
    dest="${SESSION_HOME}/${target}"
  else
    dest="${SESSION_HOME}/_unclaimed/${code}"
    unclaimed=$(( unclaimed + 1 ))
    echo "[session-sync] (待认领) ${code} -> ${dest}  提示: 两端路径不同,代码加一条 ROOT_MAP"
  fi
  mkdir -p "${dest}"
  before="$(ls "${dest}"/*.jsonl 2>/dev/null | wc -l)"
  cp -f "${src}"/*.jsonl "${dest}/"
  after="$(ls "${dest}"/*.jsonl 2>/dev/null | wc -l)"
  echo "[session-sync] 导入 ${code}  ->  ${dest}  (新增 $(( after - before )) 个会话)"
  restored=$(( restored + 1 ))
done

echo "[session-sync] 导入完成:处理 ${restored} 个会话目录"
if [ "${unclaimed}" -gt 0 ]; then
  echo
  echo "  ⚠ ${unclaimed} 个目录未能自动归位(两端根路径不同)。"
  echo "    在 settings.sh 里加一条 ROOT_MAP 后再 pull 即可自动放入,例如:"
  echo "      declare -A ROOT_MAP=( [\"/home/alen\"]=\"/home/fengye\" )"
fi
echo "[session-sync] 用 claude --resume (或重启会话) 即可继续别机的对话"