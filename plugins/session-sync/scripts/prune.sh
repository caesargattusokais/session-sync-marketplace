#!/usr/bin/env bash
# =====================================================================
# 停滞会话清理 —— 保守版:默认仅【报告】候选,不会删除任何东西。
#
# 判定一个共享会话为「停滞候选」需同时满足:
#   - 共享仓库里该编码目录最后一次被 git touch 距今超过 PRUNE_DAYS 天;
#   - 本机当前没有它的对应目录(说明本机早已不带这份会话);
#   - 它也没有落在本机 _unclaimed 里。
# 注意:我们无法得知远端其他机器是否仍持有它,故默认绝不自动删。
# 确认删除: `prune.sh --delete`(会真的删除共享仓库里这些候选目录)。
# =====================================================================
set -uo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${PLUGIN_DIR}/config.sh"

[ -d "${SHARE_ROOT}/sessions" ] || { echo "[session-sync] 没有 sessions/,无需清理"; exit 0; }

mode="report"
for a in "$@"; do case "${a}" in --delete|-d) mode="delete" ;; esac; done

now="$(date +%s)"; cands=0
for sd in "${SHARE_ROOT}"/sessions/*/; do
  [ -d "${sd}" ] || continue
  code="$(basename "${sd}")"
  ls "${sd}"/*.jsonl >/dev/null 2>&1 || continue
  case "${code}" in _*) continue ;; esac

  ts="$(git -C "${SHARE_ROOT}" log -1 --format=%ct -- "sessions/${code}" 2>/dev/null)"
  [ -n "${ts}" ] || continue                       # 尚无 git 历史(刚加入),跳过
  age=$(( (now - ts) / 86400 ))

  has_local=no
  if [ -f "${SESSION_HOME}/${code}"/*.jsonl ] 2>/dev/null || [ -n "$(ls "${SESSION_HOME}/${code}"/*.jsonl 2>/dev/null)" ]; then
    has_local=yes
  fi
  [ "${has_local}" = "yes" ] && continue

  # 本机 _unclaimed 里可再认领的,不列
  ls "${SESSION_HOME}/_unclaimed/${code}"/*.jsonl >/dev/null 2>&1 && continue

  [ "${age}" -le "${PRUNE_DAYS}" ] && continue

  cands=$(( cands + 1 ))
  echo "[session-sync] 停滞候选: ${code}  (无改动 ${age} 天, 本机无此目录)"
  if [ "${mode}" = "delete" ]; then
    rm -rf "${sd}"
    echo "              -> 已从共享仓库删除"
  fi
done

echo "[session-sync] 完成: 候选 ${cands} 个"
if [ "${mode}" = "report" ] && [ "${cands}" -gt 0 ]; then
  echo "  这只是报告,没删任何东西。确认后运行 prune.sh --delete 才真正删除。"
  echo "  (提示: 另一端仍持有的会话不建议手动删,请确认后再 --delete。)"
fi