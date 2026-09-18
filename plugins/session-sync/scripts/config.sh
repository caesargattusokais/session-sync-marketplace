#!/usr/bin/env bash
# =====================================================================
# session-sync 配置加载器(A 模式:自动归位,无需逐项目映射)。
# 只会读取各机私有配置 ~/.config/session-sync/settings.sh,请勿改本加载器。
#
# settings.sh 可含字段:
#   SESSION_HOME   本机 ~/.claude/projects(一般保持默认)
#   SHARE_ROOT     共享会话仓库在本机的路径
#   ROOT_MAP       可选「远端根 -> 本机根」替换规则(关联数组)
#   GIT_USER/EMAIL git 提交身份(仅插件自动 commit 用)
#   SANITIZE       1=导出时对会话里的密钥做脱敏(默认 1;0 关闭)
#   PRUNE_DAYS     停滞清理的「无改动天数」阈值(默认 30;仅 dry-run 报告)
#   DEBUG_HOST     手动指定“主机标识”(默认取 hostname)
#   ALLOW_PUBLIC_PUSH  1=显式放行向公开 GitHub 仓库 push(默认拦截,见 gitutil.sh)
# =====================================================================

SESSION_SYNC_CONF="${SESSION_SYNC_CONF:-$HOME/.config/session-sync/settings.sh}"

declare -A ROOT_MAP=()
SESSION_HOME=""
SHARE_ROOT=""
GIT_USER=""
GIT_EMAIL=""
SANITIZE=""
PRUNE_DAYS=""
DEBUG_HOST=""
ALLOW_PUBLIC_PUSH=""

if [ -f "${SESSION_SYNC_CONF}" ]; then
  # shellcheck disable=SC1090
  source "${SESSION_SYNC_CONF}"
fi

SESSION_HOME="${SESSION_HOME:-$HOME/.claude/projects}"
SHARE_ROOT="${SHARE_ROOT:-$HOME/session-sync-share}"
GIT_USER="${GIT_USER:-session-sync}"
GIT_EMAIL="${GIT_EMAIL:-session-sync@local}"
SANITIZE="${SANITIZE:-1}"
PRUNE_DAYS="${PRUNE_DAYS:-30}"
ALLOW_PUBLIC_PUSH="${ALLOW_PUBLIC_PUSH:-0}"
DEBUG_HOST="${DEBUG_HOST:-$(hostname 2>/dev/null || echo "unknown-host")}"