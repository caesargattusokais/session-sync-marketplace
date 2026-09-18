#!/usr/bin/env bash
# =====================================================================
# session-sync 安装引导 —— 每个安装者填写「你自己的」设置。
#
# 特性:
#   1) 可反复运行,不会整体覆盖已有配置(合并语义):
#      - 已有 settings 保留;仅更新本次给出的项。
#      - 命令行: bash setup.sh [SHARE_ROOT] [--remote=URL] [ALIAS=/path] ...
#      - 交互:  无参数且终端可交互时逐项填(留空=保留当前)。
#   2) 自动把「共享会话仓库」整备为 git 仓库:
#      - 目录不存在/空 → 有 remote 则 clone,否则本地 git init + 首个提交。
#      - 给出 --remote=URL → 自动 git remote add origin,并提示 push。
#
# 配置写到 $HOME/.config/session-sync/settings.sh(插件包之外)。
# =====================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/pathcode.sh"

CONF="${SESSION_SYNC_CONF:-$HOME/.config/session-sync/settings.sh}"

# ---- 1. 加载已有配置(只作为起始值,合并用) ----
declare -A PROJECTS=()
SHARE=""; REMOTE=""; GIT_USER=""; GIT_EMAIL=""; SESSION_HOME=""
if [ -f "${CONF}" ]; then
  # shellcheck disable=SC1090
  source "${CONF}"
  echo "[session-sync] 读取已有配置 ${CONF} (将合并更新)"
else
  echo "[session-sync] 新配置将写到: ${CONF}"
fi
SESSION_HOME="${SESSION_HOME:-$HOME/.claude/projects}"
# 配置里键名是 SHARE_ROOT,统一用内部变量 SHARE 承载 <-> 读旧值时兼容
SHARE="${SHARE_ROOT:-$SHARE}"
SHARE="${SHARE:-$HOME/session-sync-share}"

# ---- 2. 命令行覆盖/新增 ----
updated=0
if [ "$#" -gt 0 ]; then
  if [ "${1#-}" = "$1" ] && [[ "${1}" != *=* ]]; then   # 位置参数: SHARE_ROOT(非 flag 非 alias)
    SHARE="$1"; updated=1; shift
  fi
  while [ "$#" -gt 0 ]; do
    item="$1"; shift
    case "${item}" in
      --remote=*)  REMOTE="${item#--remote=}"; updated=1 ;;
      *=*)  alias="${item%%=*}"; path="${item#*=}"
            if [ -n "${alias}" ] && [ -n "${path}" ]; then
              PROJECTS["${alias}"]="${path}"; updated=1
              echo "[session-sync] 映射 ${alias} -> ${path}"
            else echo "  [跳过] 未识别参数: $item" >&2; fi ;;
      *) echo "  [跳过] 未识别参数: $item" >&2 ;;
    esac
  done
fi

# ---- 3. 交互模式(仅当终端可交互且未给任何参数) ----
if [ -t 0 ] && [ "$#" -eq 0 ] && [ "${updated}" -eq 0 ]; then
  printf '共享仓库路径(回车保留默认 %s): ' "$SHARE"
  read -r _p; [ -n "${_p}" ] && SHARE="${_p}"
  printf '共享会话仓库远端 URL(回车跳过,如 https://github.com/you/sessionsync.git): '
  read -r _r; [ -n "${_r}" ] && REMOTE="${_r}"

  echo "=== 当前项目映射 ==="
  for a in "${!PROJECTS[@]}"; do echo "  ${a} -> ${PROJECTS[$a]}"; done
  echo "添加/修改「别名 + 本机绝对路径」(空别名结束):"
  while :; do
    printf '  别名: '; read -r alias
    [ -n "${alias}" ] || break
    printf '  本机绝对路径(空=删除该别名): '; read -r path
    if [ -n "${path}" ]; then
      PROJECTS["${alias}"]="${path}"
      echo "  [session-sync] 映射 ${alias} -> ${path}  (编码: $(path_encode "$path"))"
    else
      unset 'PROJECTS[${alias}]'; echo "  已删除别名 ${alias}"
    fi
  done
fi

# ---- 4. 写回配置 ----
mkdir -p "$(dirname "${CONF}")"
{
  echo "# 由 session-sync scripts/setup.sh 生成/更新。每个安装者填自己的值(重跑可合并更新)。"
  echo "SESSION_HOME=\"${SESSION_HOME}\""
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
echo "  项目映射: ${#PROJECTS[@]} 个"
[ -n "${REMOTE}" ] && echo "  远端 URL  = ${REMOTE}"

# ---- 5. 自动化整备共享会话仓库(git init / clone + remote add) ----
mkdir -p "$(dirname "${SHARE}")"
if [ -d "${SHARE}/.git" ]; then
  echo "[session-sync] 共享仓库已是 git 仓库: ${SHARE}"
elif [ ! -d "${SHARE}" ] || [ -z "$(ls -A "${SHARE}" 2>/dev/null)" ]; then
  if [ -n "${REMOTE}" ]; then
    git clone -q "${REMOTE}" "${SHARE}" && echo "[session-sync] 已 clone 共享仓库: ${REMOTE}"
  else
    mkdir -p "${SHARE}"
    git -C "${SHARE}" init -q
    git -C "${SHARE}" -c user.name="${GIT_USER:-session-sync}" -c user.email="${GIT_EMAIL:-session-sync@local}" \
        commit --allow-empty -qm 'session-sync init'
    echo "[session-sync] 已在本机新建共享仓库: git init + 首个提交"
  fi
else
  echo "[session-sync] 注意: ${SHARE} 非空且非 git 仓库,跳过自动 init(请手动处理)"
fi

# 确保 origin
if [ -n "${REMOTE}" ] && [ -d "${SHARE}/.git" ]; then
  if git -C "${SHARE}" remote get-url origin >/dev/null 2>&1; then
    echo "[session-sync] origin 已存在 -> $(git -C "${SHARE}" remote get-url origin)"
  else
    git -C "${SHARE}" remote add origin "${REMOTE}" && echo "[session-sync] 已 add origin -> ${REMOTE}"
  fi
  br="$(git -C "${SHARE}" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  if [ -z "${br}" ] || [ "${br}" = "HEAD" ]; then
    echo "  [提示] 此仓库尚无任何提交;git -C \"${SHARE}\" 里先提交一次再 push:"
    echo "        git -C \"${SHARE}\" commit -m session-sync-init && git -C \"${SHARE}\" push -u origin master"
  elif [ -z "$(git -C "${SHARE}" config --get "branch.${br}.remote")" ]; then
    echo "  [下一步] git -C \"${SHARE}\" push -u origin ${br}"
  fi
fi

if [ "${#PROJECTS[@]}" -eq 0 ]; then
  echo "[session-sync] 尚无项目映射;可交互或传参重跑,例如:"
  echo "  bash setup.sh ${SHARE} --remote=<你的仓库URL> myrepo=\"${HOME}/some/project\""
fi