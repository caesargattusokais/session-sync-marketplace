#!/usr/bin/env bash
# 导出本机「全部」会话到共享仓库 sessions/。A 模式:不做过滤、不做映射。
# 特性: 脱敏(SANITIZE)、来源标记(host)、push 冲突自愈(gitutil)。
set -uo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${PLUGIN_DIR}/config.sh"
source "${PLUGIN_DIR}/lock.sh"
source "${PLUGIN_DIR}/sanitize.sh"
source "${PLUGIN_DIR}/gitutil.sh"

acquire_lock || exit 0

[ -d "${SESSION_HOME}" ] || { echo "[session-sync] 未发现会话目录 ${SESSION_HOME}"; exit 0; }

mkdir -p "${SHARE_ROOT}/sessions"
cd "${SHARE_ROOT}"

exported=0
for codedir in "${SESSION_HOME}"/*/; do
  [ -d "${codedir}" ] || continue
  code="$(basename "${codedir}")"
  case "${code}" in _*) continue ;; esac      # 跳过 _unclaimed 等内部目录
  [ "${code}" = "." ] && continue
  ls "${codedir}"/*.jsonl >/dev/null 2>&1 || continue

  dst="${SHARE_ROOT}/sessions/${code}"
  mkdir -p "${dst}"

  # 脱敏复制(不碰源文件);SANITIZE=0 时原样复制
  redacted=0
  for f in "${codedir}"/*.jsonl; do
    [ -e "${f}" ] || continue
    if [ "${SANITIZE}" = "1" ]; then
      if [ -f "${dst}/$(basename "${f}")" ] && cmp -s "${f}" "${dst}/$(basename "${f}")"; then
        cp -f "${f}" "${dst}/$(basename "${f}")"
      else
        sanitize_file "${f}" "${dst}/$(basename "${f}")"
        redacted=$(( redacted + 1 ))
      fi
    else
      cp -f "${f}" "${dst}/$(basename "${f}")"
    fi
  done

  # 来源标记(本次由哪台主机导出)。仅当「host/sanitize 身份」变化时才写:
  # 同一台机反复导出内容不变,不写 → 避免每轮 session 结束都因时间戳产生空提交。
  _ident="host=${DEBUG_HOST} sanitize=$([ "${SANITIZE}" = "1" ] && echo yes || echo no)"
  if [ ! -f "${dst}/.source" ] || ! grep -qF "${_ident}" "${dst}/.source"; then
    printf 'host=%s date=%s sanitize=%s\n' "${DEBUG_HOST}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$([ "${SANITIZE}" = "1" ] && echo yes || echo no)" > "${dst}/.source"
  fi

  n="$(ls "${dst}"/*.jsonl 2>/dev/null | wc -l)"
  [ "${redacted}" -gt 0 ] && note=" (脱敏 ${redacted} 份)" || note=""
  echo "[session-sync] 导出 ${code} -> sessions/${code}  (${n} 会话${note})"
  exported=$(( exported + 1 ))
done
[ "${exported}" -eq 0 ] && echo "[session-sync] 本机没有找到任何可导出的会话"

if git rev-parse --git-dir >/dev/null 2>&1; then
  git add sessions
  if git diff --cached --quiet; then
    echo "[session-sync] 无变更,不提交"
  else
    git -c user.name="${GIT_USER}" -c user.email="${GIT_EMAIL}" \
        commit -m "session-sync: export $(date -u +%Y-%m-%dT%H:%M:%SZ)" >/dev/null
    gitutil_push
  fi
else
  echo "[session-sync] ${SHARE_ROOT} 不是 git 仓库;已写入文件,待同步手段处理"
fi