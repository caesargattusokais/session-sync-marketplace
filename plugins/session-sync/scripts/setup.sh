#!/usr/bin/env bash
# =====================================================================
# session-sync 安装引导 —— 每个安装者运行一次,填写「你自己的」设置。
#
# 动态提示;也可简洁地传参一次性完成(适合脚本化):
#   bash setup.sh [SHARE_ROOT] [ALIAS=/abs/path] [ALIAS2=/abs/path2 ...]
#
# 生成的配置写到 $HOME/.config/session-sync/settings.sh(插件包之外)。
# =====================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/pathcode.sh"

CONF="${SESSION_SYNC_CONF:-$HOME/.config/session-sync/settings.sh}"
[ -f "${CONF}" ] && echo "[session-sync] 已存在 ${CONF},将被覆盖。" || echo "[session-sync] 配置将写到: ${CONF}"

interactive()
{
  [ -t 0 ] && [ "$#" -eq 0 ]
}

declare -A PROJECTS=()

if interactive "$@"; then
  printf '共享仓库在本机的 clone 路径(回车用默认 %s): ' "${HOME}/session-sync-share"
  read -r SHARE
  SHARE="${SHARE:-$HOME/session-sync-share}"
  echo "逐个填写「项目别名」与「本机绝对路径」(空行结束):"
  while :; do
    printf '  别名: '; read -r alias
    [ -n "${alias}" ] || break
    printf '  本机绝对路径: '; read -r path
    [ -n "${path}" ] || { echo "  (未填路径,跳过)"; continue; }
    echo "  [session-sync 映射] ${alias} -> ${path}  (编码: $(path_encode "$path"))"
    PROJECTS["${alias}"]="${path}"
  done
else
  SHARE="${1:-$HOME/session-sync-share}"
  shift || true
  while [ "$#" -gt 0 ]; do
    item="$1"
    alias="${item%%=*}"
    path="${item#*=}"
    if [ -n "${alias}" ] && [ -n "${path}" ]; then
      PROJECTS["${alias}"]="${path}"
    else
      echo "  [跳过] 未识别参数: $item" >&2
    fi
    shift
  done
fi

mkdir -p "$(dirname "${CONF}")"
{
  echo "# 由 session-sync 的 scripts/setup.sh 生成。每个安装者填自己的值。"
  echo "SESSION_HOME=\"${SESSION_HOME:-${HOME}/.claude/projects}\""
  echo "SHARE_ROOT=\"${SHARE}\""
  echo "GIT_USER=\"${GIT_USER:-session-sync}\""
  echo "GIT_EMAIL=\"${GIT_EMAIL:-session-sync@local}\""
  echo "declare -A PROJECTS=("
  for alias in "${!PROJECTS[@]}"; do
    printf '  ["%s"]="%s"\n' "$alias" "${PROJECTS[$alias]}"
  done
  echo ")"
} > "${CONF}"

echo "[session-sync] 已写入 ${CONF}:"
echo "  SHARE_ROOT = ${SHARE}"
echo "  项目映射: ${#PROJECTS[@]} 个 (别名 -> 本机路径)"
if [ "${#PROJECTS[@]}" -eq 0 ]; then
  echo "  警告: 尚未填写任何项目别名。可用参数重跑,例如:"
  echo "    bash setup.sh ${HOME}/session-sync-share myrepo=${HOME}/some/project"
fi

echo
echo "下一步(自己的远程仓库):"
echo "  1) git init ${SHARE} && cd ${SHARE} && git commit --allow-empty -m init"
echo "     git remote add origin <你那个共享会话的私有仓库URL> && git push -u origin HEAD"
echo "  2) 每台机器这里填入各自的配置后,即可 /session-sync push|pull"