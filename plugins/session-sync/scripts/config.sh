#!/usr/bin/env bash
# =====================================================================
# session-sync 配置 —— 每台机器都要填写这份文件的本机值。
#
# 【核心原则】PROJECTS 这个映射表里:
#   - 左边的「别名」是跨机器共享的钥匙(两端必须一致)。
#   - 右边的「绝对路径」是这台机器自己的(两端可以不同)。
# 会话以「别名」为键在几台机器之间来回归位,因此两端路径不同也没关系。
# =====================================================================

# 本机 Claude Code 会话目录(一般保持默认)
SESSION_HOME="${SESSION_HOME:-$HOME/.claude/projects}"

# 共享仓库在本机的 clone 路径。
# 两端各自把同一个 git 私有仓库 clone 到这里(README 里有 clone 命令)。
SHARE_ROOT="${SHARE_ROOT:-$HOME/session-sync-share}"

# git 提交身份(仅用于本插件自动 commit,可任意)
GIT_USER="${GIT_USER:-session-sync}"
GIT_EMAIL="${GIT_EMAIL:-session-sync@local}"

# ---------------------------------------------------------------------
# 项目别名 -> 本机绝对路径。
# 改成你自己的;一个项目一行。两端别名的 key 必须一致,value 填各自本机。
#   declare -A PROJECTS=(
#     ["myproj"]="/home/fengye/myproj"
#     ["other"]="/workspace/other"
#   )
# ---------------------------------------------------------------------
declare -A PROJECTS=(
  ["example"]="/home/fengye/example-project"
)