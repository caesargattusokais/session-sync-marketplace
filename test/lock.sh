#!/usr/bin/env bash
# =====================================================================
# 进程锁(scripts/lock.sh)单元测试:正常获取/释放、遗留锁自愈、他人在用不强抢。
# 独立子进程运行,避免 EXIT trap 与其它测试互相覆盖。
# 用法: bash test/lock.sh
# =====================================================================
set -uo pipefail

S="$(cd "$(dirname "${BASH_SOURCE[0]}")/../plugins/session-sync" && pwd)"
SIM="$(mktemp -d)"; trap 'rm -rf "$SIM"' EXIT

SHARE_ROOT="${SIM}/share"          # 提前对 source 的 lock.sh 生效
source "${S}/scripts/lock.sh"
source "${S}/scripts/gitutil.sh"

PASS=0; FAIL=0
ok(){  echo "  ✓ $1"; PASS=$((PASS+1)); }
bad(){ echo "  ✗ FAIL: $1"; FAIL=$((FAIL+1)); }

# 1. 正常获取/释放
if acquire_lock; then ok "进程锁可获取"; else bad "进程锁获取失败"; fi
[ -d "${LOCK_DIR}" ] || bad "获取后锁目录应存在"
release_lock
[ ! -d "${LOCK_DIR}" ] && ok "release_lock 移除锁目录" || bad "release_lock 未移除锁目录"

# 2. 遗留锁自愈:持锁 PID 已死 → 应自动清除并抢到
mkdir -p "${LOCK_DIR}"; echo 999999 > "${LOCK_DIR}/pid"
if acquire_lock; then ok "遗留锁(持锁进程已死)自动清除并抢到"; else bad "遗留锁未能自愈"; fi
release_lock

# 3. 他人在用:不应强抢,超时返回 1;且不误删他人锁
_LOCK_MAX=3; _LOCK_SLEEP=0.05        # 缩小超时,加速测试
mkdir -p "${LOCK_DIR}"; echo "$$" > "${LOCK_DIR}/pid"
if acquire_lock; then bad "他人持有的锁被错误抢到"; else ok "他人持有锁时不强抢(超时放弃)"; fi
[ -d "${LOCK_DIR}" ] && ok "失败释放未误删他人锁" || bad "失败释放误删了他人锁"
unset _LOCK_MAX _LOCK_SLEEP

# 4. 公开 GitHub 仓库 → 推送闸门拦截;显式放行/非 GitHub 则放行
PUB="${SIM}/pubgate"; git init -q "${PUB}"; git -C "${PUB}" remote add origin https://github.com/acme/leak.git
gh(){ printf 'PUBLIC\n'; }                 # gh 桩(真实 gh 返回大写):命令被公开
if ALLOW_PUBLIC_PUSH=0 SHARE_ROOT="${PUB}" gitutil_guard_public; then
  bad "公开 GitHub 仓库未被安全闸拦截"
else
  ok "公开 GitHub 仓库被安全拦截"
fi
if ALLOW_PUBLIC_PUSH=1 SHARE_ROOT="${PUB}" gitutil_guard_public; then
  ok "ALLOW_PUBLIC_PUSH=1 显式放行"
else
  bad "显式放行仍被拦截"
fi
PRIV="${SIM}/priv"; git init -q "${PRIV}"; git -C "${PRIV}" remote add origin ssh://other.example/x/y.git
if ALLOW_PUBLIC_PUSH=0 SHARE_ROOT="${PRIV}" gitutil_guard_public; then
  ok "非 GitHub remote 放行(无从判断)"
else
  bad "非 GitHub remote 被误拦"
fi
gh(){ printf 'PRIVATE\n'; }                # 真实 gh 私有返回(大写):必须放行
if ALLOW_PUBLIC_PUSH=0 SHARE_ROOT="${PUB}" gitutil_guard_public; then
  ok "私有仓库(大写 PRIVATE)不被误拦"
else
  bad "私有仓库被误拦"
fi
gh() { return 127; }                            # 恢复:gh 不可用也要放行(无法判断)
if ALLOW_PUBLIC_PUSH=0 SHARE_ROOT="${PUB}" gitutil_guard_public; then
  ok "gh 不可用时放行并提示,不硬卡"
else
  bad "gh 不可用时被误拦"
fi
rm -f "${HOME}/.config/session-sync/.public-blocked"

echo
echo "── 锁/安全测试: PASS=${PASS} FAIL=${FAIL} ──"
[ "${FAIL}" -eq 0 ] || exit 1
echo "ALL PASSED"