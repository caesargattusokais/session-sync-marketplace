#!/usr/bin/env bash
# 导出本机会话:把 PROJECTS 映射的各项目会话,按【别名】推送到共享仓库。
set -uo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${PLUGIN_DIR}/config.sh"
source "${PLUGIN_DIR}/pathcode.sh"

[ "${#PROJECTS[@]}" -gt 0 ] || { echo "[session-sync] config.sh 里 PROJECTS 为空,先填写映射"; exit 1; }

mkdir -p "${SHARE_ROOT}/sessions"
cd "${SHARE_ROOT}"

for alias in "${!PROJECTS[@]}"; do
  local_path="${PROJECTS[$alias]}"
  code="$(path_encode "${local_path}")"
  src="${SESSION_HOME}/${code}"
  dst="${SHARE_ROOT}/sessions/${alias}"
  mkdir -p "${dst}"
  if [ -d "${src}" ] && ls "${src}"/*.jsonl >/dev/null 2>&1; then
    cp -f "${src}"/*.jsonl "${dst}/"
    n="$(ls "${dst}"/*.jsonl 2>/dev/null | wc -l)"
    echo "[session-sync] 导出 alias='${alias}'  ->  ${dst}  (${n} 个会话)"
  else
    echo "[session-sync] 跳过 alias='${alias}'  (本机无 ${src})"
  fi
done

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