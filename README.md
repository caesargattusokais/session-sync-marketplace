# session-sync — 跨机器共享 Claude Code 会话的插件

把本机的 Claude Code 会话(`~/.claude/projects/*.jsonl`)按**项目别名**同步到多台机器。
会话以「别名」为键归位,所以**各机器绝对路径不同也没有关系**,两端 `claude --resume` 都能续上同一个对话。

**设计原则:每个安装者填自己的。** 插件包内不含任何仓库地址 / 路径 / 身份默认值。
每台机器运行一次 `scripts/setup.sh`,把安装者**自己**的共享仓库与项目映射写进
`~/.config/session-sync/settings.sh`(插件包之外),多人安装互不干扰,插件升级也不覆盖配置。

## 目录结构

```
session-sync-marketplace/            ← 这里是 git 私有仓库,推到安装者各自的 GitHub
├── .claude-plugin/marketplace.json  ← 分发目录(marketplace)
└── plugins/session-sync/
    ├── .claude-plugin/plugin.json
    ├── hooks/hooks.json             ← SessionStart→import / SessionEnd→export(自动同步)
    ├── scripts/
    │   ├── config.sh                ← 配置加载器(别改),读各机自己的 settings.sh
    │   ├── setup.sh                 ← 【每个安装者运行一次】填自己的仓库+路径
    │   ├── export.sh                ← 本机会话 -> 共享仓库
    │   ├── import.sh                ← 共享仓库 -> 本机归位
    │   └── pathcode.sh              ← 绝对路径 <-> cwd 编码 互转
    └── skills/session-sync/SKILL.md ← 手动命令 /session-sync setup|push|pull
```

## 工作原理

1. 会话文件在 `~/.claude/projects/<cwd编码>/<sessionId>.jsonl`,`<cwd编码>` 是启动目录
   绝对路径转成 `-home-fengye-proj` 这类字符串。
2. 会话身份 = 「cwd 编码目录」+「文件名里的 sessionId」。把 A 机某个 `.jsonl` 放到
   B 机对应项目目录下、文件名不变,B 机就能 `--resume` 原样续聊。
3. 本插件把搬运自动化:共享仓库里按**项目别名**分目录存会话,每机 import 按自己路径归位。

## 每台机器要做的(≈4 步)

### 1. 安装插件(每台各一次)
```bash
claude plugin marketplace add <插件所在仓库或本地路径>
claude plugin install session-sync@<marketplace>
```
装好后插件落在各机本地;`~/.config/session-sync/settings.sh` 由你在下一步自己生成,
不跟在插件包里。

### 2. 用 setup 填自己本机的配置
```bash
# 交互式:
bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh"
# 或一次性传参:
bash ~/.claude/plugins/cache/<市场名>/plugins/session-sync/scripts/setup.sh \
     "$HOME/session-sync-share"  myrepo="$HOME/myproject"  other="/workspace/other"
```
这会生成 `~/.config/session-sync/settings.sh`,含:
- `SHARE_ROOT` : 本机这个「共享会话仓库」的路径
- `PROJECTS`   : 项目**别名** -> 本机绝对路径(别名是跨机共享的钥匙,两端一致;路径各自填)

### 3. 建好自己的共享会话仓库(git 私有仓库,推你自己的 GitHub)
```bash
git init "$HOME/session-sync-share" && cd "$HOME/session-sync-share"
git commit --allow-empty -m init
git remote add origin <你的共享会话仓库 URL> && git push -u origin HEAD
```
> 「插件仓库」和「共享会话仓库」可以不同名——都需要你 `git init` 后推你自己的 GitHub。
> 本机测试阶段共享仓库没有 remote 也能用(脚本会落在本地,另一台再 pull)。

### 4. 使用
- 手动:`/session-sync push` / `/session-sync pull`
- 自动:hook 在会话开始(SessionStart)拉、结束(SessionEnd)推
  (不想要自动同步,删掉插件里的 `hooks/hooks.json` 即可只用手动)。

## 限制(请知悉)

- 会话 jsonl 里的「工具调用绝对路径」是导出机器的;跨机后**续聊、读上下文完全正常**,
  但要让 B 机脚本直接操作原路径的文件,需保证 B 机该路径下也有文件。
- hook 全自动同步;网络/仓库不可达时改用手动 `/session-sync`。