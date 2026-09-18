#!/usr/bin/env bash
# =====================================================================
# 单机进程级互斥锁(可移植:用 mkdir 的原子性;Windows Git Bash 也有)。
# 用途:一台机器开多个会话,两个 SessionEnd hook 几乎同时触发时,两个
# export.sh 会在同一个共享仓库上并发跑 git,撞 .git/index.lock → 仅靠
# gitutil 的「跨机」自愈救不了本地这轮。这里把同一仓库的操作串行化。
# 锁目录按 SHARE_ROOT 编码放到系统临时目录:不同共享仓库互不阻塞。
#
# 崩溃自愈:锁目录里写入持有进程 PID。抢不到时若发现持有 PID 已死,
# 判定为遗留锁并清除重试——避免持锁进程被 SIGKILL/超时杀掉后永久卡死。
# 依赖 config.sh(用到 $SHARE_ROOT)。
# =====================================================================

[ -n "${_LOCK_SH:-}" ] && return 0
_LOCK_SH=1

_LOCK_BASE="${LOCK_ROOT:-${TMPDIR:-/tmp}/session-sync-locks}"
_lock_name="$(printf '%s' "${SHARE_ROOT}" | perl -pe 's/[^A-Za-z0-9]+/-/g')"
LOCK_DIR="${_LOCK_BASE}/${_lock_name}"

_LOCK_ACQ=0
_LOCK_MAX=50        # 最多等 50 次
_LOCK_SLEEP=0.2     # 每次 0.2s → 最长约 10s

# 判定当前持锁者是否已死(→ 遗留锁,可清除)
_lock_stale() {
  local pid
  [ -f "${LOCK_DIR}/pid" ] || return 1      # 无 pid 标记 → 不算遗留,继续等
  pid="$(cat "${LOCK_DIR}/pid" 2>/dev/null)" || return 1
  [ "${pid}" = "$$" ] && return 1           # 自己?异常,不判遗留
  kill -0 "${pid}" 2>/dev/null && return 1  # 还活着 → 不是遗留
  return 0                                  # 已死 → 遗留
}

# 抢锁;成功返回 0 并注册 EXIT 释放。超时返回 1,调用方应放弃本轮。
acquire_lock() {
  mkdir -p "${_LOCK_BASE}" 2>/dev/null || true
  local n=0
  while ! mkdir "${LOCK_DIR}" 2>/dev/null; do
    if _lock_stale; then
      rm -rf "${LOCK_DIR}"
      continue
    fi
    n=$(( n + 1 ))
    if [ "${n}" -ge "${_LOCK_MAX}" ]; then
      echo "[session-sync] 等待另一会话同步结束超时,本轮跳过(${LOCK_DIR})" >&2
      return 1
    fi
    sleep "${_LOCK_SLEEP}"
  done
  printf '%s\n' "$$" > "${LOCK_DIR}/pid"
  _LOCK_ACQ=1
  trap release_lock EXIT
  return 0
}

release_lock() {
  if [ "${_LOCK_ACQ}" -eq 1 ]; then
    rm -rf "${LOCK_DIR}"
    _LOCK_ACQ=0
  fi
}