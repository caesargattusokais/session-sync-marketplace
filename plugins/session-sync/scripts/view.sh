#!/usr/bin/env bash
# =====================================================================
# 会话浏览器(只读):浏览共享仓库 sessions/ 里的全部会话(跨机)。
#
#   view.sh list   [--json|-t] [--q TERM] [--host TERM] [--pull]
#   view.sh show   <sessionId> [--html] [--no-thinking] [--full]
#   view.sh export <outdir>    [--no-thinking] [--pull]
#
# list    列会话元信息(表 / --json / -t tsv)。
# show    把单条 transcript 还原成可读文本(--html 出单页)。
# export  生成 index.html + 每个会话一个 .html,可浏览器翻阅。
# 全部只读共享仓库(脱敏副本),不动本机源。-pull 先拉远端最新。
# 依赖 bash + perl(跨平台自带)。
# =====================================================================
set -uo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${PLUGIN_DIR}/config.sh"

TRANS="${PLUGIN_DIR}/transcript.pl"
[ -d "${SHARE_ROOT}/sessions" ] || { echo "[session-sync] 共享仓库里还没有 sessions/(先 push 或 pull)。" >&2; exit 1; }

cmd="${1:-}"; [ -n "${cmd}" ] || { echo "用法: view.sh list|show|export …" >&2; exit 1; }
shift

# 由 ROOT_MAP 构建 "src:dst" 参数,供 perl 把远端项目路径映射成本机路径展示
map_args=()
for _k in "${!ROOT_MAP[@]}"; do
  map_args+=(--root-map "${_k}:${ROOT_MAP[$_k]}")
done

find_session_file() {
  local id="$1" d f n=0 cand=""
  id="${id%.jsonl}"
  for d in "${SHARE_ROOT}"/sessions/*/; do
    [ -d "${d}" ] || continue
    [ -f "${d}/${id}.jsonl" ] && { echo "${d}/${id}.jsonl"; return 0; }
  done
  for d in "${SHARE_ROOT}"/sessions/*/; do
    for f in "${d}/${id}"*.jsonl; do
      [ -f "${f}" ] || continue
      n=$(( n + 1 )); cand="${f}"
    done
  done
  [ "${n}" -eq 1 ] && { echo "${cand}"; return 0; }
  [ "${n}" -gt 1 ] && echo "匹配到多个会话(前缀太短),加长 sessionId 再试:" >&2
  return 1
}

do_pull() {
  source "${PLUGIN_DIR}/gitutil.sh"; gitutil_pull || true
}

has() { local a; for a in "$@"; do [ "$a" = "${2:-}" ] && return 0; done; return 1; }

case "${cmd}" in
  list|ls)
    if [ "${1:-}" = "--pull" ]; then do_pull; shift; fi
    pass=(); fmt=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --json) fmt=--json ;;
        -t|--tsv) fmt=--tsv ;;
        --host) shift; pass+=(--host-f "${1:-}") ;;
        --q) shift; pass+=(--q "${1:-}") ;;
        --pull) ;;
        *) pass+=("$1") ;;
      esac
      shift
    done
    # shellcheck disable=SC2086
    perl "${TRANS}" --inventory "${SHARE_ROOT}/sessions" "${map_args[@]+"${map_args[@]}"}" ${fmt} "${pass[@]+"${pass[@]}"}"
    ;;
  show)
    id="${1:-}"; shift || true
    [ -n "${id}" ] || { echo "用法: view.sh show <sessionId> [--html]…" >&2; exit 1; }
    opts=()
    for a in "$@"; do case "$a" in --html) opts+=(--format=html) ;; --no-thinking) opts+=(--no-thinking) ;; --full) opts+=(--full) ;; esac; done
    f="$(find_session_file "${id}")" || { echo "未找到会话 ${id}" >&2; exit 1; }
    # transcript.pl 会自行读 .source 拿 host,无需传
    perl "${TRANS}" "${f}" "${opts[@]+"${opts[@]}"}"
    ;;
  export)
    out="${1:-}"; shift || true
    [ -n "${out}" ] || { echo "用法: view.sh export <outdir> [--no-thinking]" >&2; exit 1; }
    if [ "${1:-}" = "--pull" ]; then do_pull; shift; fi
    nth=""; for a in "$@"; do [ "$a" = "--no-thinking" ] && nth=--no-thinking; done
    mkdir -p "${out}"
    tsv="$(perl "${TRANS}" --inventory "${SHARE_ROOT}/sessions" "${map_args[@]+"${map_args[@]}"}" --tsv)"
    rows=""; n=0
    while IFS=$'\t' read -r id host date proj title cost nuser nassist ntool; do
      f="$(find_session_file "${id}")" || continue
      perl "${TRANS}" "${f}" --format=html ${nth} --host "${host}" > "${out}/${id}.html"
      rows="${rows}
<tr><td><a href='${id}.html'>${id}</a></td><td>${host}</td><td>${date%%T*}</td><td>${proj}</td><td>${title}</td><td>${cost}</td><td>${nuser}/${nassist}/${ntool}</td></tr>"
      n=$(( n + 1 ))
    done <<< "${tsv}"
    {
      printf '<!DOCTYPE html><html><head><meta charset="utf-8"><title>session-sync 会话索引</title>'
      printf '<style>body{font-family:system-ui,sans-serif;margin:2em auto;max-width:1100px}'
      printf 'table{border-collapse:collapse;width:100%%}th,td{border:1px solid #e1e4e8;padding:6px 10px;text-align:left;'
      printf 'font-size:13px;word-break:break-all}th{background:#f6f8fa}td a{font-family:monospace;font-size:11px}</style></head><body>'
      printf '<h1>session-sync 会话索引(%d 条)</h1><table><tr><th>sessionId</th><th>host</th><th>date</th><th>project</th><th>title</th><th>cost$</th><th>u/a/tool</th></tr>%s</table></body></html>\n' \
        "${n}" "${rows}"
    } > "${out}/index.html"
    echo "[session-sync] 已导出 ${n} 个会话到 ${out}/ (打开 index.html)"
    ;;
  *)
    echo "未知命令: ${cmd} (可用 list | show | export)" >&2; exit 1;;
esac