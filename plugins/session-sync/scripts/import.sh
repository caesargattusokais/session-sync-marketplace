#!/usr/bin/env bash
# 导入共享会话:从共享仓库按【别名】拉取,归位到本机各项目的 cwd 编码目录,
# 这样本机 claude --resume 就能续上别台机器导出的会话。
set -uo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${PLUGIN_DIR}/config.sh"
source "${PLUGIN_DIR}/pathcode.sh"

[ "${#PROJECTS[@]}" -gt 0 ] || { echo "[session-sync] config.sh 里 PROJECTS 为空,先填写映射"; exit 1; }

# 先拉取远端共享仓库(不存在则直接遍历本地文件)
if [ -d "${SHARE_ROOT}" ] && git -C "${SHARE_ROOT}" rev-parse --git-dir >/dev/null 2>&1; then
  git -C "${SHARE_ROOT}" pull --quiet 2>/dev/null \
    && echo "[session-sync] 已从共享仓库拉取" \
    || echo "[session-sync] (无 remote 或拉取失败,使用本地缓存)"
fi

restored=0
for alias in "${!PROJECTS[@]}"; do
  local_path="${PROJECTS[$alias]}"
  code="$(path_encode "${local_path}")"
  dest="${SESSION_HOME}/${code}"
  src="${SHARE_ROOT}/sessions/${alias}"
  mkdir -p "${dest}"
  if [ -d "${src}" ] && ls "${src}"/*.jsonl >/dev/null 2>&1; then
    before="$(ls "${dest}"/*.jsonl 2>/dev/null | wc -l)"
    cp -f "${src}"/*.jsonl "${dest}/"
    after="$(ls "${dest}"/*.jsonl 2>/dev/null | wc -l)"
    added=$(( after - before ))
    echo "[session-sync] 导入 alias='${alias}' -> ${dest}  (新增 ${added} 个会话)"
    restored=$(( restored + added ))
  fi
done

echo "[session-sync] 完成。重启会话或用 claude --resume 即可继续别机的对话(新增 ${restored} 个)"