#!/usr/bin/env bash
# =====================================================================
# 共享仓库的 git 并发/冲突自愈工具。
# 两台机器同时工作时,sh对面 push 会被拒(non-fast-forward)。
# 这里统一处理:push 被拒→自动 pull --rebase 后重推;pull 失败→明确提示。
# 所有函数依赖 config.sh 已 source(用到 $SHARE_ROOT / $GIT_USER 等)。
# =====================================================================

# 共享仓库 pull(rebase + autostash,避免本地未提交被卡住)
gitutil_pull() {
  if [ -d "${SHARE_ROOT}/.git" ]; then
    git -C "${SHARE_ROOT}" pull --rebase --autostash --quiet 2>/dev/null \
      && return 0 \
      || { echo "[session-sync] 警告: 共享仓库 pull 出现问题(可能有冲突或网络异常)。" >&2;
           echo "  请手动处理: git -C \"${SHARE_ROOT}\" pull --rebase" >&2;
           sleep 1; return 1; }
  fi
  return 0
}

# 共享仓库 push:失败则 pull --rebase 后重试,最多 N 轮
gitutil_push() {
  [ -d "${SHARE_ROOT}/.git" ] || { echo "[session-sync] ${SHARE_ROOT} 不是 git 仓库,跳过 push"; return 0; }
  git -C "${SHARE_ROOT}" remote -v | grep -q . || { echo "[session-sync] 共享仓库无 remote,只见提交未推送"; return 0; }

  local n=0
  until git -C "${SHARE_ROOT}" push --quiet 2>/dev/null; do
    n=$(( n + 1 ))
    if [ ${n} -ge 4 ]; then
      echo "[session-sync] push 多次失败,请手动处理: git -C \"${SHARE_ROOT}\" status" >&2
      return 1
    fi
    echo "[session-sync] push 被拒(non-fast-forward),自动 pull --rebase 后重试 ..."
    if git -C "${SHARE_ROOT}" pull --rebase --autostash --quiet 2>/dev/null; then
      sleep 1
    else
      git -C "${SHARE_ROOT}" rebase --abort 2>/dev/null || true
      echo "[session-sync] rebase 出现冲突,已中止;请手动解决后再 push: git -C \"${SHARE_ROOT}\" pull --rebase" >&2
      return 1
    fi
  done
  echo "[session-sync] 已推送"
  return 0
}