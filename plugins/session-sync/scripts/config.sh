#!/usr/bin/env bash
# =====================================================================
# session-sync 配置加载器(A 模式:自动归位,无需逐项目映射)。
#
# 每台机器的**私有配置**放在插件包之外:
#     $HOME/.config/session-sync/settings.sh
# 由 `scripts/setup.sh` 引导生成(本文件只会读取它,请勿改本加载器)。
#
# settings.sh 可含的字段:
#   SESSION_HOME         本机 ~/.claude/projects(一般保持默认)
#   SHARE_ROOT           共享会话仓库在本机的路径
#   ROOT_MAP             可选「远端根 -> 本机根」替换规则(关联数组)
#   GIT_USER / GIT_EMAIL git 提交身份(仅插件自动 commit 用)
#
# ROOT_MAP 为空 = 两台机器的会话绝对路径完全相同,可直接精确归位;
# 若两端路径不同,加一条即可。例:
#   declare -A ROOT_MAP=( ["/home/alen"]="/home/fengye" )
#   表示「远端 /home/alen 开头的会话,在本机放到 /home/fengye 下对应的位置」。
# =====================================================================

SESSION_SYNC_CONF="${SESSION_SYNC_CONF:-$HOME/.config/session-sync/settings.sh}"

declare -A ROOT_MAP=()
SESSION_HOME=""
SHARE_ROOT=""
GIT_USER=""
GIT_EMAIL=""

if [ -f "${SESSION_SYNC_CONF}" ]; then
  # shellcheck disable=SC1090
  source "${SESSION_SYNC_CONF}"
fi

SESSION_HOME="${SESSION_HOME:-$HOME/.claude/projects}"
SHARE_ROOT="${SHARE_ROOT:-$HOME/session-sync-share}"
GIT_USER="${GIT_USER:-session-sync}"
GIT_EMAIL="${GIT_EMAIL:-session-sync@local}"