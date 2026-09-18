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

# 推送前安全闸:默认禁止把会话自动 push 到 GitHub 公开仓库。
# 会话含工具调用/代码原文,而 SANITIZE 只是正则级脱敏,公开=完整泄露,又进 git 历史洗不掉。
# 仅当 gh 能确证「公开」时拦截;非 GitHub remote / gh 不可用 → 无从判断,放行(文档建议私有)。
# 确证公开已拦截一次后写标记文件,后续每轮只简短提醒、仍拦截。ALLOW_PUBLIC_PUSH=1 显式放行。
gitutil_guard_public() {
  [ "${ALLOW_PUBLIC_PUSH:-0}" = "1" ] && return 0
  local remote repo vis
  remote="$(git -C "${SHARE_ROOT}" config --get remote.origin.url 2>/dev/null)" || return 0
  [[ "${remote}" == *github.com* ]] || return 0         # 非 GitHub remote,无从判断,放行
  repo="${remote##*github.com[:/]}"; repo="${repo%.git}"
  vis="$(gh repo view "${repo}" --json visibility --jq .visibility 2>/dev/null)" \
    || { echo "[session-sync] 无法校验共享仓库可见性(gh 不可用),请自行确认它保持私有。" >&2; return 0; }
  if [ "${vis}" = "public" ]; then
    warnfile="${HOME}/.config/session-sync/.public-blocked"
    mkdir -p "$(dirname "${warnfile}")" 2>/dev/null || true
    if [ ! -f "${warnfile}" ]; then
      echo "[session-sync] ✗ 安全拦截: 共享仓库 ${repo} 是【公开】仓库,拒绝自动 push 会话内容。
  · 会话含工具调用/代码原文,SANITIZE 只是正则级脱敏,推上去=完整泄露,且进 git 历史删不净。
  · 请把共享仓库改成 private;或自担风险在 settings.sh 加 ALLOW_PUBLIC_PUSH=1 显式放行。" >&2
      : > "${warnfile}"
    else
      echo "[session-sync] 共享仓库仍是公开的,已拦截自动 push(${repo})。放行: settings.sh 加 ALLOW_PUBLIC_PUSH=1。" >&2
    fi
    return 1
  fi
  return 0
}

# 共享仓库 push:失败则 pull --rebase 后重试,最多 N 轮
gitutil_push() {
  [ -d "${SHARE_ROOT}/.git" ] || { echo "[session-sync] ${SHARE_ROOT} 不是 git 仓库,跳过 push"; return 0; }
  git -C "${SHARE_ROOT}" remote -v | grep -q . || { echo "[session-sync] 共享仓库无 remote,只见提交未推送"; return 0; }

  gitutil_guard_public || return 1

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