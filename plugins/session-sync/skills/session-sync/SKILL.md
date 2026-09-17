---
name: session-sync
description: 跨机器同步 Claude Code 会话记录,支持跨绝对路径恢复续聊
argument-hint: [push | pull]
disable-model-invocation: false
user-invocable: true
allowed-tools: Bash(bash *)
---

# Session Sync

跨机器共享本机的 Claude Code 会话(`~/.claude/projects/` 下的 .jsonl)。
本插件把会话按「项目别名」推进/拉出共享 git 仓库,并按本机路径归位:
无论各机器的绝对路径是否相同,`claude --resume` 都能续上别机导出的对话。

## 用法

- `/session-sync push`  → 导出本机会话到共享仓库(hook 在 SessionEnd 也会自动做)
- `/session-sync pull`  → 从共享仓库拉取并归位(hook 在 SessionStart 也会自动做)

## 执行

请用 Bash 工具运行插件自带脚本(避免权限弹窗,脚本路径已在 allowed-tools 预批准):

- push:
  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/export.sh"
  ```
- pull:
  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/import.sh"
  ```

若用户未配置,请先提示编辑 `${CLAUDE_PLUGIN_ROOT}/scripts/config.sh` 里的
`PROJECTS` 映射(别名两端一致,路径填各自本机的)。