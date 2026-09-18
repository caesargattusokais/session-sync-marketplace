#!/usr/bin/env bash
# =====================================================================
# session-sync 安装引导(A 模式:自动归位,零/极简配置)。
#
# 无需逐项目映射。除共享仓库外,只有一件事可选:「根替换规则」。
#   - 两台机器会话绝对路径相同 → 什么都不用填,直接 push/pull。
#   - 不同(如 /home/alen vs /home/fengye) → 填一条:远端根 -> 本机根。
#
# 用法:
#   bash setup.sh                              # 交互式
#   bash setup.sh [SHARE_ROOT] [--remote=URL]  # 命令行(ROOT_MAP 留到交互/改文件)
#
# 会顺便把共享会话仓库 git init / clone 并 add origin(见 5)。
# 配置写到 $HOME/.config/session-sync/settings.sh(插件包之外)。
# =====================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="${SESSION_SYNC_CONF:-$HOME/.config/session-sync/settings.sh}"

# ---- 1. 读已有,作合并底子 ----
declare -A ROOT_MAP=()
SHARE=""; REMOTE=""; GIT_USER=""; GIT_EMAIL=""; SESSION_HOME=""
if [ -f "${CONF}" ]; then
  # shellcheck disable=SC1090
  source "${CONF}"
  echo "[session-sync] 读取已有配置 ${CONF} (将合并更新)"
else
  echo "[session-sync] 新配置将写到: ${CONF}"
fi
SESSION_HOME="${SESSION_HOME:-$HOME/.claude/projects}"
SHARE="${SHARE_ROOT:-$SHARE}"
SHARE="${SHARE:-$HOME/session-sync-share}"

# ---- 2. 命令行参数 ----
updated=0
if [ "$#" -gt 0 ]; then
  if [ "${1#-}" = "$1" ] && [[ "${1}" != --* ]]; then SHARE="$1"; updated=1; shift; fi
  for a in "$@"; do
    case "${a}" in
      --remote=*) REMOTE="${a#--remote=}"; updated=1 ;;
      *) echo "  [跳过] 未识别参数: $a" >&2 ;;
    esac
  done
fi

# ---- 3. 交互模式(可选根替换) ----
if [ -t 0 ] && [ "$#" -eq 0 ] && [ "${updated}" -eq 0 ]; then
  printf '共享仓库路径(回车默认 %s): ' "$SHARE"
  read -r _p; [ -n "${_p}" ] && SHARE="${_p}"
  printf '共享会话仓库远端 URL(回车跳过): '
  read -r _r; [ -n "${_r}" ] && REMOTE="${_r}"
  echo "=== 根替换规则(可空) ==="
  echo "两端会话绝对路径相同(如同一用户名/同一目录布局)=> 直接回车.enter"
  for k in "${!ROOT_MAP[@]}"; do echo "  现有: ${k} -> ${ROOT_MAP[$k]}"; done
  echo "逐条输入: 远端根 [+空格] 本机根  (空回车结束;例如 '/home/alen /home/fengye'):"
  while :; do
    printf '  远端根 本机根: '; read -r rp lp
    [ -n "${rp}" ] || break
    if [ -n "${lp}" ]; then ROOT_MAP["${rp}"]="${lp}"; echo "  [映射] ${rp} -> ${lp}"; else echo "  (少了本机根,跳过)"; fi
  done
fi

# ---- 4. 写回配置 ----
mkdir -p "$(dirname "${CONF}")"
{
  echo "# 由 session-sync scripts/setup.sh 生成/更新(A 模式:零/极简)。"
  echo "SESSION_HOME=\"${SESSION_HOME}\""
  echo "SHARE_ROOT=\"${SHARE}\""
  echo "GIT_USER=\"${GIT_USER:-session-sync}\""
  echo "GIT_EMAIL=\"${GIT_EMAIL:-session-sync@local}\""
  echo "declare -A ROOT_MAP=("
  for k in "${!ROOT_MAP[@]}"; do
    printf '  ["%s"]="%s"\n' "$k" "${ROOT_MAP[$k]}"
  done
  echo ")"
} > "${CONF}"
echo "[session-sync] 已写入 ${CONF} (SHARE_ROOT=${SHARE}; 根替换 ${#ROOT_MAP[@]} 条)"

# ---- 5. 自动整备共享会话仓库(git init / clone + remote add) ----
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
  echo "[session-sync] 注意: ${SHARE} 非空且非 git 仓库,跳过自动 init (请手动处理)"
fi

if [ -n "${REMOTE}" ] && [ -d "${SHARE}/.git" ]; then
  if git -C "${SHARE}" remote get-url origin >/dev/null 2>&1; then
    echo "[session-sync] origin 已存在 -> $(git -C "${SHARE}" remote get-url origin)"
  else
    git -C "${SHARE}" remote add origin "${REMOTE}" && echo "[session-sync] 已 add origin -> ${REMOTE}"
  fi
  br="$(git -C "${SHARE}" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  if [ -n "${br}" ] && [ "${br}" != "HEAD" ] && [ -z "$(git -C "${SHARE}" config --get "branch.${br}.remote")" ]; then
    echo "  [下一步] git -C \"${SHARE}\" push -u origin ${br}"
  fi
fi

# ---- 6. 共享仓库可见性提醒:若是 GitHub 公开仓库,红字警告会话将公开 ----
gh_scan_visibility() {
  command -v gh >/dev/null 2>&1 || return 0
  local remote full owner repo vis
  remote="$(git -C "${SHARE}" config --get remote.origin.url 2>/dev/null || true)"
  [[ "${remote}" == *github.com* ]] || return 0
  full="${remote##*github.com/}"; full="${full%.git}"
  owner="${full%%/*}"; repo="${full#*/}"
  vis="$(gh repo view "${owner}/${repo}" --json visibility -q .visibility 2>/dev/null || true)"
  if [ "${vis}" = "public" ]; then
    echo
    echo "  ⚠️  远端 ${owner}/${repo} 是【公开】仓库。会话将被整包明文上传,"
    echo "      其中可能含 token/密码。强烈建议改用【私有】仓库。"
  fi
}
gh_scan_visibility

echo
echo "好了,可以开始用了:  /session-sync push  /  /session-sync pull"
echo "两端路径不同的话,再给 settings.sh 补一条 ROOT_MAP 即可(见文件头注释)。"