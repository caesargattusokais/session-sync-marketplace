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
#   IDENTITY_ROOTS    本机各项目 checkout 的根(换行分隔)。空=自动($HOME+盘根),
#                     由自动归位(项目身份)扫描;通常无需设置
#   IDENTITY_SCAN_DEPTH 上述根下扫描 git checkout 的目录层数(默认 3)
#   IDENTITY_CACHE_TTL  身份索引缓存秒数(默认 21600=6h)
# =====================================================================

SESSION_SYNC_CONF="${SESSION_SYNC_CONF:-$HOME/.config/session-sync/settings.sh}"

declare -A ROOT_MAP=()
SESSION_HOME=""
SHARE_ROOT=""
GIT_USER=""
GIT_EMAIL=""
SANITIZE=""
SHARD_MAX=""
PRUNE_DAYS=""
DEBUG_HOST=""
ALLOW_PUBLIC_PUSH=""
IDENTITY_ROOTS=""
IDENTITY_SCAN_DEPTH=""
IDENTITY_CACHE_TTL=""
IDENTITY_CACHE_FILE=""

if [ -f "${SESSION_SYNC_CONF}" ]; then
  # shellcheck disable=SC1090
  source "${SESSION_SYNC_CONF}"
fi

SESSION_HOME="${SESSION_HOME:-$HOME/.claude/projects}"
SHARE_ROOT="${SHARE_ROOT:-$HOME/session-sync-share}"
GIT_USER="${GIT_USER:-session-sync}"
GIT_EMAIL="${GIT_EMAIL:-session-sync@local}"
SANITIZE="${SANITIZE:-1}"
# 共享仓里单个会话文件超过该字节数则分片存储(session-share 默认走 git+GitHub,
# 其单文件硬限 100MB;取 90MB 留余量,避免 push 被 pre-receive 拒。90 000 000B)
SHARD_MAX="${SHARD_MAX:-90000000}"
PRUNE_DAYS="${PRUNE_DAYS:-30}"
ALLOW_PUBLIC_PUSH="${ALLOW_PUBLIC_PUSH:-0}"
DEBUG_HOST="${DEBUG_HOST:-$(hostname 2>/dev/null || echo "unknown-host")}"
IDENTITY_SCAN_DEPTH="${IDENTITY_SCAN_DEPTH:-3}"
IDENTITY_CACHE_TTL="${IDENTITY_CACHE_TTL:-21600}"
IDENTITY_CACHE_FILE="${IDENTITY_CACHE_FILE:-$HOME/.config/session-sync/.identity-cache}"