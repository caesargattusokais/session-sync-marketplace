---
name: session-sync
description: 跨机器同步 Claude Code 会话记录,支持跨绝对路径恢复续聊
argument-hint: [setup | push | pull]
disable-model-invocation: false
user-invocable: true
allowed-tools: Bash(bash *)
---

# Session Sync

跨机器共享本机的 Claude Code 会话(`~/.claude/projects/` 下的 .jsonl)。
自动归位,无需逐项目映射:导出默认包含全部会话,导入时用「本机已有同编码路径」
或一条可选的「根替换规则 ROOT_MAP」自动放回对应项目,`claude --resume` 即可续聊。

> 配置在插件包之外(`~/.config/session-sync/settings.sh`),各机各一份,互不覆盖。

## 用法

- `/session-sync setup [SHARE_ROOT] [--remote=URL]` → 首次必做,填自己的共享仓库;可选根替换
- `/session-sync push` → 导出本机全部会话到共享仓库(hook 在 SessionEnd 也会做)
- `/session-sync pull` → 从共享仓库拉取并自动归位(hook 在 SessionStart 也会做)

## 执行(脚本在 allowed-tools 已预批准)

- setup:
  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh" <SHARE_ROOT> [--remote=<自己的共享仓库URL>]
  ```
  两端会话路径不同时,提示用户再加一条根替换(在 settings.sh 或交互填):
  `declare -A ROOT_MAP=( ["/home/alen"]="/home/fengye" )`  # 远端根 -> 本机根

- push:
  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/export.sh"
  ```
- pull:
  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/import.sh"
  ```

规则:两端绝对路径相同 → 零配置;不同 → 一条 ROOT_MAP;未命中 → 进 `_unclaimed/`,补规则后再 pull。