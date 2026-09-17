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
本插件把会话按「项目别名」推进/拉出**每个安装者自己的**共享仓库,并按本机路径归位:
无论各机器的绝对路径是否相同,`claude --resume` 都能续上别机导出的对话。

> 多人各装一份,互不干扰:每个安装者用自己的 `setup` 填自己的仓库路径与项目映射,
> 配置存在插件包之外(`~/.config/session-sync/settings.sh`),不会互相覆盖、插件升级也保留。

## 用法

- `/session-sync setup [SHARE_ROOT] [ALIAS=/path ...]` → **首次必须**。填写自己本机的共享仓库路径与项目映射
- `/session-sync push` → 导出本机会话到共享仓库(hook 在 SessionEnd 也会自动做)
- `/session-sync pull` → 从共享仓库拉取并归位(hook 在 SessionStart 也会自动做)

## 执行(脚本在 allowed-tools 已预批准)

- setup(告诉用户先填映射,再给仓库地址):
  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh <SHARE_ROOT> <别名>=<本机绝对路径> ..."
  ```
  例:`bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh" "$HOME/session-sync-share" myrepo="$HOME/myproject"`

- push:
  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/export.sh"
  ```
- pull:
  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/import.sh"
  ```

setup 之后,若共享仓库还没在本地,提示用户:
`git init "${SHARE_ROOT}" && cd "${SHARE_ROOT}" && git remote add origin <安装者自己的共享会话仓库URL>`
(把「那个序列化的会话文件仓库」地址换成用户自己的)。