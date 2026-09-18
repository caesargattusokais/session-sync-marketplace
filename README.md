# session-sync — 跨机器共享 Claude Code 会话的插件

把本机的 Claude Code 会话(`~/.claude/projects/*.jsonl`)同步到多台机器,**自动归位、
无需逐项目映射**。两端 `claude --resume` 都能续上同一个对话——即使各机器绝对路径不同。

**A 模式原则:用户只管装、只管用。**
- 导出默认包含**全部**本地会话。
- 导入自动归位:两端路径相同 = 零配置;不同 = 一条可选的「根替换规则」。
- 没命中规则 → 放进 `_unclaimed/` 待认领,不丢、不阻塞,补规则再 pull 即自动归位。

## 目录结构

```
session-sync-marketplace/
├── .claude-plugin/marketplace.json
└── plugins/session-sync/
    ├── .claude-plugin/plugin.json
    ├── hooks/hooks.json           ← SessionStart→import / SessionEnd→export
    ├── scripts/
    │   ├── config.sh             ← 配置加载器(别改),读各机 settings.sh
    │   ├── setup.sh              ← 【每机运行一次】填共享仓库(+可选根替换)
    │   ├── export.sh             ← 导出本机全部会话 -> 共享仓库
    │   ├── import.sh             ← 共享仓库 -> 自动归位到本机
    │   └── pathcode.sh           ← cwd 编码工具
    └── skills/session-sync/SKILL.md
```

## 怎么工作

1. 会话在 `~/.claude/projects/<cwd编码>/<sessionId>.jsonl`,编码 = 启动绝对路径的 `-a-b-c` 形式。
2. 会话身份 = 「cwd 编码目录」+「文件名里的 sessionId」。把 A 机某 `.jsonl` 放到 B 机对应项目的
   编码目录下、名不变,B 机 `--resume` 就能续聊。
3. 本插件导出全部(无过滤),导入时按下面优先级归位:
   - 本机已有同名编码目录 → 直接放(两端路径相同,零配置)
   - ROOT_MAP 规则(远端根→本机根)命中 → 解码后映射归位
   - 否则 → `_unclaimed/`,提示补规则

## 每台机器安装(≈3 步)

### 1. 装插件
```bash
claude plugin marketplace add <插件所在仓库或本地路径>
claude plugin install session-sync@<marketplace>
```

### 2. 填自己的共享仓库(各机一次)
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh" "$HOME/session-sync-share" \
     --remote=<你自己的共享会话仓库URL>
```
- 交互模式可顺手填「根替换规则」(只有两端路径不同时才需要,可空)。
- 生成的 settings 在 `~/.config/session-sync/settings.sh`(插件包外,升级不覆盖)。

### 3. 用
- 手动:`/session-sync push` / `/session-sync pull`
- 自动:hook 在 SessionStart 拉、SessionEnd 推;不想要就删 `hooks/hooks.json`。

「共享会话仓库」和「插件仓库」可不同名,各自 git init 后推你自己的 (建议私有) GitHub。

## 根替换规则(什么时候需要、怎么写)

两台机器**会话绝对路径相同**(如同一用户名、同一目录布局) → **不用写**。
不同(如 `/home/alen` vs `/home/fengye`),在 settings.sh 加一条即可:
```bash
declare -A ROOT_MAP=( ["/home/alen"]="/home/fengye" )
```
含义:凡是远端 `/home/alen` 下的会话(含其子目录),在本机放到 `/home/fengye` 对应位置。

## 跨平台(Linux / macOS / Windows 原生)

- **编码不依赖平台**:`cwd_encode` 先把 Windows 反斜杠 `\` 归一为正斜杠 `/`,再折叠非字母数字段,
  所以 `C:/Users/me/proj`、`C:\Users\me\proj`、`/home/fengye` 跨平台编码一致——
  同一项目在 Windows 与 Linux 两端也能自动归位。
- **hooks 用 exec 形式**(hook 定义里 `command: bash` + `args: ["${CLAUDE_PLUGIN_ROOT}/scripts/*.sh"]`),
  避免不同平台引号/路径转义差异。
- **Windows 原生(非 WSL)必须装 Git for Windows**:脚本是 bash,靠它自带的 Git Bash 在 hook /
  skill 里执行(`shell: bash`)。没有 Git Bash(纯 PowerShell)时 hook 会被跳过、skill 不可用。
- **macOS** 未用 BSD 专属命令(`date -Is` 等已改为 `date -u +...`),开箱即用。

## 内置特性(都默认开启/可选)

- **脱敏(SANITIZE=1,默认)** —— 导出的是把明显密钥(GitHub PAT / OpenAI key / AWS / Slack /
  password / secret)替换成 `<REDACTED:...>` 的副本,**本机原文件不动**。需要原始内容时可设 `SANITIZE=0`。
- **冲突自愈** —— 两台机器同时工作时,push 被拒会自动 `pull --rebase --autostash` 后重试;pull 失败给明确提示。
- **来源标记(host)** —— 每份导出的会话记下是「哪台主机、何时、是否脱敏」导出的,`sessions/<编码>/.source`,pull 时展示来源。
- **停滞清理(/session-sync prune)** —— 报告「共享里有但本机没有、且多日未更新(默认 30 天)」的会话;默认**只报告不删**,确认后加 `--delete` 才真删(害怕误删另一端在用的,不建议自动删)。
- **CI(可选)** —— `test/e2e.sh` 端到端回归 + GitHub Actions(`.github/workflows/test.yml`)自动跑语法检查与测试。

## 限制(请知悉)

- 会话 jsonl 里的「工具调用绝对路径」是导出机器的;跨机后**续聊、读上下文完全正常**,
  但要让 B 机脚本直接操作原路径文件,需保证 B 机该路径下也有文件。
- 历史会话**整包明文**进入共享仓库;共享仓库务必用**私有**,避免泄露 token/项目私密。
- 共享仓库建议私有(用户自己的多台设备之间同步,私有完全够,还更安全)。