#!/usr/bin/env bash
# 绝对路径 <-> Claude Code 项目目录编码 互转。
# Claude Code 用 cwd 编码作为 ~/.claude/projects/ 下的目录名:
#   /home/fengye            -> -home-fengye
#   /home/fengye/code/foo   -> -home-fengye-code-foo

# 路径 -> 编码
path_encode() {
  local p="${1}"
  p="${p#/}"            # 去掉开头斜杠
  p="${p//\//-}"        # 其余 / -> -
  echo "-${p}"
}