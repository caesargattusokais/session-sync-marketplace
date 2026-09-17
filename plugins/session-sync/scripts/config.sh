#!/usr/bin/env bash
# =====================================================================
# session-sync 配置加载器(只读这份文件,不要改它)。
#
# 每台机器的**私有配置**放在插件包之外:
#     $HOME/.config/session-sync/settings.sh
# 由 `scripts/setup.sh` 引导每个安装者填写自己机器上的值
# (共享仓库路径/remote、项目别名<->本机路径、git 提交身份)。
#
# 这样多人安装同一份插件互不干扰,插件升级也不会覆盖各自的配置。
# =====================================================================

# 私有配置文件路径(可用环境变量覆盖,便于测试)
SESSION_SYNC_CONF="${SESSION_SYNC_CONF:-$HOME/.config/session-sync/settings.sh}"

# 先假定空映射,若存在私有配置则加载进来(会被其中的 declare 覆盖)
declare -A PROJECTS=()

if [ -f "${SESSION_SYNC_CONF}" ]; then
  # shellcheck disable=SC1090
  source "${SESSION_SYNC_CONF}"
elif [ "${SESSION_SYNC_STRICT:-0}" = "1" ]; then
  echo "[session-sync] 未找到配置 ${SESSION_SYNC_CONF}。请先运行 scripts/setup.sh 填写你自己的设置。" >&2
  exit 1
fi

# 其余项的默认值(可被 settings.sh 覆盖)
SESSION_HOME="${SESSION_HOME:-$HOME/.claude/projects}"
SHARE_ROOT="${SHARE_ROOT:-$HOME/session-sync-share}"
GIT_USER="${GIT_USER:-session-sync}"
GIT_EMAIL="${GIT_EMAIL:-session-sync@local}"