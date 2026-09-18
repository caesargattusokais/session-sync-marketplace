#!/usr/bin/env bash
# 导出本机「全部」会话:把 ~/.claude/projects 下每个 cwd 编码目录的 .jsonl
# 按编码目录名复制到共享仓库 sessions/ 下。不做任何过滤,不带任何映射——
# 映射与归位全部交给 import 端(见 import.sh)。A 模式:对用户零配置。
set -uo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${PLUGIN_DIR}/config.sh"

[ -d "${SESSION_HOME}" ] || { echo "[session-sync] 未发现会话目录 ${SESSION_HOME} (可能从没开过会话)"; exit 0; }

mkdir -p "${SHARE_ROOT}/sessions"
cd "${SHARE_ROOT}"

exported=0
for codedir in "${SESSION_HOME}"/*/; do
  [ -d "${codedir}" ] || continue
  code="$(basename "${codedir}")"
  # 跳过我们的内部目录(如 _unclaimed)等以下划线开头的非项目目录
  case "${code}" in _*) continue ;; esac
  [ "${code}" = "." ] && continue
  ls "${codedir}"/*.jsonl >/dev/null 2>&1 || continue

  dst="${SHARE_ROOT}/sessions/${code}"
  mkdir -p "${dst}"
  cp -f "${codedir}"/*.jsonl "${dst}/"
  n="$(ls "${dst}"/*.jsonl 2>/dev/null | wc -l)"
  echo "[session-sync] 导出 ${code}  ->  sessions/${code}  (${n} 个会话)"
  exported=$(( exported + 1 ))
done
[ "${exported}" -eq 0 ] && echo "[session-sync] 本机没有找到任何可导出的会话"

# 提交并推送(git 私有仓库即为同步介质)
if git rev-parse --git-dir >/dev/null 2>&1; then
  git add sessions
  if git diff --cached --quiet; then
    echo "[session-sync] 无变更,不提交"
  else
    git -c user.name="${GIT_USER}" -c user.email="${GIT_EMAIL}" \
        commit -m "session-sync: export $(date -Is)" >/dev/null
    if git remote -v | grep -q .; then
      git push >/dev/null 2>&1 && echo "[session-sync] 已推送"
    else
      echo "[session-sync] 已提交(本仓库未配置 remote,未推送)"
    fi
  fi
else
  echo "[session-sync] ${SHARE_ROOT} 不是 git 仓库;已写入文件,待同步手段处理"
fi