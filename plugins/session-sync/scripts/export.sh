#!/usr/bin/env bash
# 导出本机「全部」会话到共享仓库 sessions/。A 模式:不做过滤、不做映射。
# 特性: 脱敏(SANITIZE)、来源标记(host)、push 冲突自愈(gitutil)。
set -uo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${PLUGIN_DIR}/config.sh"
source "${PLUGIN_DIR}/lock.sh"
source "${PLUGIN_DIR}/sanitize.sh"
source "${PLUGIN_DIR}/gitutil.sh"
source "${PLUGIN_DIR}/identity.sh"

acquire_lock || exit 0

[ -d "${SESSION_HOME}" ] || { echo "[session-sync] 未发现会话目录 ${SESSION_HOME}"; exit 0; }

mkdir -p "${SHARE_ROOT}/sessions"
cd "${SHARE_ROOT}"

# 会话文件 sha(GitHub pre-receive 之外的去重依据:源未变则不重切,避免大文件每轮都产生提交)
sh_sha() { sha256sum "$1" 2>/dev/null | cut -d' ' -f1 || md5sum "$1" 2>/dev/null | cut -d' ' -f1 || echo ""; }

# <src_file> <dst_dir> <id> <base> :把已脱敏的 src_file 按字节切成 <SHARD_MAX 字节的 part_* 分片,
# 写 manifest .shard;源 sha 未变则跳过(不重切)。分片目录形如 sessions/<code>/<id>/,导入时按序拼回。
shard_session() {
  local srcfile="$1" dstdir="$2" id="$3" base="$4" manifest cursha npart
  manifest="${dstdir}/${id}/.shard"
  cursha="$(sh_sha "${srcfile}")"
  if [ -f "${manifest}" ] && [ "$(sed -n 's/^src_sha=//p' "${manifest}")" = "${cursha}" ]; then
    return 0
  fi
  mkdir -p "${dstdir}/${id}"
  rm -f "${dstdir}/${id}"/part_*
  split -b "${SHARD_MAX}" -d -a 3 "${srcfile}" "${dstdir}/${id}/part_"
  npart="$(ls "${dstdir}/${id}"/part_* 2>/dev/null | wc -l)"
  rm -f "${dstdir}/${base}"      # 顶掉旧的单文件形态
  printf 'name=%s\nparts=%s\nsrc_sha=%s\n' "${id}" "${npart}" "${cursha}" > "${manifest}"
}

exported=0
for codedir in "${SESSION_HOME}"/*/; do
  [ -d "${codedir}" ] || continue
  code="$(basename "${codedir}")"
  case "${code}" in _*) continue ;; esac      # 跳过 _unclaimed 等内部目录
  [ "${code}" = "." ] && continue
  ls "${codedir}"/*.jsonl >/dev/null 2>&1 || continue

  dst="${SHARE_ROOT}/sessions/${code}"
  mkdir -p "${dst}"

  # 脱敏复制(不碰源文件);SANITIZE=0 时原样复制;超 SHARD_MAX 的会话改分片存储。
  redacted=0; sharded=0
  for f in "${codedir}"/*.jsonl; do
    [ -e "${f}" ] || continue
    base="$(basename "${f}")"; id="${base%.jsonl}"
    if [ "${SANITIZE}" = "1" ]; then
      if [ -f "${dst}/${base}" ] && cmp -s "${f}" "${dst}/${base}"; then
        src="${dst}/${base}"                      # 已是脱敏副本且内容未变,复用
      else
        sanitize_file "${f}" "${dst}/${base}"
        src="${dst}/${base}"; redacted=$(( redacted + 1 ))
      fi
    else
      src="${f}"
    fi

    sz="$(wc -c < "${src}" 2>/dev/null || echo 0)"
    if [ "${sz}" -gt "${SHARD_MAX}" ]; then
      shard_session "${src}" "${dst}" "${id}" "${base}"
      sharded=$(( sharded + 1 ))
    else
      [ "${src}" != "${dst}/${base}" ] && cp -f "${src}" "${dst}/${base}"
      [ -d "${dst}/${id}" ] && rm -rf "${dst}/${id}"   # 清掉此前变小时残留的分片目录
    fi
  done

  # 来源标记(本次由哪台主机导出)。仅当「host/sanitize 身份」变化时才写:
  # 同一台机反复导出内容不变,不写 → 避免每轮 session 结束都因时间戳产生空提交。
  _ident="host=${DEBUG_HOST} sanitize=$([ "${SANITIZE}" = "1" ] && echo yes || echo no)"
  if [ ! -f "${dst}/.source" ] || ! grep -qF "${_ident}" "${dst}/.source"; then
    printf 'host=%s date=%s sanitize=%s\n' "${DEBUG_HOST}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$([ "${SANITIZE}" = "1" ] && echo yes || echo no)" > "${dst}/.source"
  fi

  # 项目身份(用 origin 仓库的规范化 git remote;跨机同仓库可自动归位)
  r="" tl=""
  origin_cwd="$(session_origin_cwd "${codedir}"/*.jsonl 2>/dev/null)"
  if [ -n "${origin_cwd}" ]; then
    line="$(git_identity_of "${origin_cwd}" 2>/dev/null || true)"
    [ -n "$line" ] && { tl="${line%$'\n'*}"; r="${line##*$'\n'}"; }
  fi
  if [ -n "${r}" ]; then
    if [ ! -f "${dst}/.identity" ] || \
       [ "$(cat "${dst}/.identity" 2>/dev/null)" != "$(printf 'remote=%s\ntoplevel=%s' "${r}" "${tl}")" ]; then
      printf 'remote=%s\ntoplevel=%s\n' "${r}" "${tl}" > "${dst}/.identity"
    fi
  fi

  n="$(ls "${dst}"/*.jsonl 2>/dev/null | wc -l)"
  [ "${redacted}" -gt 0 ] && note=" (脱敏 ${redacted} 份)" || note=""
  [ "${sharded}" -gt 0 ] && note="${note} (分片 ${sharded} 份)"
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