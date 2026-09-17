# session-sync — 跨机器共享 Claude Code 会话的插件

把本机的 Claude Code 会话(`~/.claude/projects/*.jsonl`)按**项目别名**同步到多台机器。
因为会话以「别名」为键归位,所以**各机器绝对路径不同也没有关系**,两端 `claude --resume` 都能续上同一个对话。

## 目录结构

```
session-sync-marketplace/            ← 这是一个 git 私有仓库,推到你自己的 GitHub
├── .claude-plugin/marketplace.json  ← 分发目录(marketplace)
└── plugins/session-sync/
    ├── .claude-plugin/plugin.json   ← 插件 manifest
    ├── hooks/hooks.json             ← SessionStart→import / SessionEnd→export(自动同步)
    ├── skills/session-sync/SKILL.md ← 手动命令 /session-sync
    └── scripts/
        ├── config.sh                ← 【每台机器填这里】共享仓库 + PROJECTS 路径映射
        ├── pathcode.sh              ← 绝对路径 <-> cwd 编码 互转
        ├── export.sh                ← 本机会话 -> 共享仓库
        └── import.sh                ← 共享仓库 -> 本机归位
```

## 工作原理

1. Claude Code 的会话文件放在 `~/.claude/projects/<cwd编码>/<sessionId>.jsonl`,其中
   `<cwd编码>` 是把启动目录的绝对路径转成 `-home-fengye-proj` 这类字符串。
2. 会话身份 = 「cwd 编码目录」+「文件名里的 sessionId(uuid)」。所以把 A 机某个
   `.jsonl` 放到 B 机对应项目的 cwd 编码目录下、文件名不变,B 机就能 `--resume` 原样续聊。
3. 本插件把这个「搬运」自动化:共享仓库里按**项目别名**分目录存各会话文件,
   每台机 import 时按自己的路径归位。别名相同、路径任意。

## 在两台机器上的安装

### 0. 准备一个 git 私有仓库(同步介质,推 GitHub 或自建 remote)
```bash
git init session-sync-share && cd session-sync-share && git commit --allow-empty -m init
# 推到远端,例如:
#   gh repo create session-sync-share --private --source=. --push
```

### 1. 装插件(两台机器各一次,macOS/Linux 里也一样)
```bash
cd /your/path
git clone <你的插件仓库> session-sync-marketplace
cd session-sync-marketplace
claude plugin marketplace add ./          # 用本地目录(local scope)
claude plugin install session-sync@session-sync-marketplace
```
> 用 GitHub owner/repo 分发(而非 marketplace.json 裸 URL)时,相对 source 才有效;
> 单人本机测试用本地目录最省事。

### 2. 填配置(两台机器都要,路径填各自的)
编辑
`~/.claude/plugins/cache/<...>/plugins/session-sync/scripts/config.sh`
或直接编辑你 clone 的 `plugins/session-sync/scripts/config.sh`:
- `SHARE_ROOT`: 共享仓库在本机的 clone 路径
- `PROJECTS`:  项目别名 -> 本机绝对路径(别名两端一致)

### 3. clone 共享仓库到本机
```bash
git clone <共享仓库 remote> $HOME/session-sync-share
```

### 4. 使用
- 手动:`/session-sync push` / `/session-sync pull`
- 自动:hook 在会话开始(SessionStart)自动拉、结束(SessionEnd)自动推,
  `config.sh` 里关掉 hook 或删掉 `hooks/hooks.json` 即可只用手动。

## 限制(请知悉)

- 会话 jsonl 里的「工具调用绝对路径」是导出机器的;跨机后**续聊、读上下文完全正常**,
  但若要让 B 机脚本直接操作原路径的文件,需保证 B 机该路径下也有文件。
- hook 默认全自动同步;若网络/仓库可达性不佳,可改用手动 `/session-sync`。