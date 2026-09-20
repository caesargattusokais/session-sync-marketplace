---
name: session-sync
description: 跨机器同步 Claude Code 会话记录,支持跨绝对路径恢复续聊
argument-hint: [setup | push | pull | prune | list | show | export]
shell: bash
disable-model-invocation: false
user-invocable: true
allowed-tools: Bash(bash *)
---

# Session Sync

跨机器共享本机的 Claude Code 会话(`~/.claude/projects/` 下的 .jsonl)。
自动归位,不依赖逐项目映射:导出默认包含全部会话,导入时按「本机已有同编码路径 / 一条可选的
根替换规则 ROOT_MAP / **项目身份(git remote,自动)** / $HOME 猜测」自动放回对应项目,`claude --resume` 即可续聊。
新 clone 仓库后重跑 `pull --rescan` 强制重建本机项目身份索引。

> 支持 Linux / macOS / Windows(Windows 原生需 Git for Windows,见 README「跨平台」)。
> 配置在插件包之外(`~/.config/session-sync/settings.sh`),各机各一份。

## 用法

- `/session-sync setup [SHARE_ROOT] [--remote=URL]` → 首次必做,填自己的共享仓库;可选根替换
- `/session-sync push`   → 导出本机全部会话到共享仓库(hook 在 SessionEnd 也会做)
- `/session-sync pull`   → 从共享仓库拉取并自动归位(hook 在 SessionStart 也会做)
- `/session-sync pull --rescan` → 强制重建本机项目身份索引后拉取归位(新 clone 仓库后跑一次即自动归位)
- `/session-sync prune [--delete]` → 报告停滞会话;确认后再加 --delete 才删
- `/session-sync list [--json|-t] [--q 词] [--host 词] [--pull]` → 列出共享仓库里全部(跨机)会话
- `/session-sync show <sessionId> [--no-thinking] [--full] [--html]` → 把单条会话还原成可读文本
- `/session-sync export <outdir> [--no-thinking]` → 生成 index.html + 每会话一页,浏览器翻阅

脱敏默认开启(SANITIZE=1):导出的是把明显密钥替换成 `<REDACTED>` 的副本,本机原文件不动。
push/pull 自带冲突自愈。list/show/export 只读脱敏副本,可直接用。Windows 原生请先装 Git for Windows。

## 执行(脚本在 allowed-tools 已预批准)

- setup:
  ```bash
  bash "${CLAUDE_SKILL_DIR}/../../scripts/setup.sh" <SHARE_ROOT> [--remote=<自己的共享仓库URL>]
  ```
  两端会话路径不同时,再补一条根替换(在 settings.sh 或交互填):
  `declare -A ROOT_MAP=( ["/home/alen"]="/home/fengye" )`  # 远端根 -> 本机根
  (Windows 用户示例:`["C:/Users/me/proj"]="/home/fengye/proj"`)

- push:
  ```bash
  bash "${CLAUDE_SKILL_DIR}/../../scripts/export.sh"
  ```
- pull:
  ```bash
  bash "${CLAUDE_SKILL_DIR}/../../scripts/import.sh"            # 自动归位(含项目身份)
  bash "${CLAUDE_SKILL_DIR}/../../scripts/import.sh" --rescan   # 新 clone 仓库后强制重建索引再归位
  ```
- prune:
  ```bash
  bash "${CLAUDE_SKILL_DIR}/../../scripts/prune.sh"
  ```
- list (查跨机会话;可加 --pull 先拉远端最新):
  ```bash
  bash "${CLAUDE_SKILL_DIR}/../../scripts/view.sh" list [--json] [-t] [--q "<词>"] [--host "<词>"] [--pull]
  ```
- show (还原单条会话,默认收起 thinking):
  ```bash
  bash "${CLAUDE_SKILL_DIR}/../../scripts/view.sh" show <sessionId> [--no-thinking] [--full] [--html]
  ```
- export (生成 index.html + 每会话一页,浏览器翻阅):
  ```bash
  bash "${CLAUDE_SKILL_DIR}/../../scripts/view.sh" export <outdir> [--no-thinking]
  ```

规则:两端绝对路径相同 → 零配置;不同 → 项目身份(git remote)自动归位,clone 仓库后跑 `pull --rescan`;
不想用启发式可写 ROOT_MAP 显式覆盖;仍未命中 → 进 `_unclaimed/`,补规则再 pull。