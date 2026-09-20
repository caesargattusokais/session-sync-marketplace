#!/usr/bin/env bash
# =====================================================================
# 项目身份工具:用「规范化 git remote」识别会话所属项目,并映射到本机
# 对应 checkout,实现跨机零配置归位(替代手动 ROOT_MAP)。
#
# 思路:一台机上「同一个项目」= 该 git 仓库的本地 checkout。会话自带
# origin 绝对路径(用户消息的 cwd),导出端用它定位 origin 仓库,toplevel
# 与 origin remote 一并写进 sessions/<code>/.identity;导入端在本机扫
# 更新本机各 git checkout 的 remote→路径索引,按 remote 命中同一仓库,
# 自动落到本机那棵 checkout,并把会话内 cwd 前缀改写成本机路径。
#
# 依赖:config.sh(IDENTITY_* 配置)、pathcode.sh(cwd_encode)已 source。
# 纯 bash + perl,零额外依赖,跨 Linux/macOS/Git-Bash。
# =====================================================================

declare -A IDENT_CACHE=()          # canonical_remote -> 本机 checkout 绝对路径

# ---------- 远程 URL 规范化(所有形态 -> "host:owner/repo",小写) ----------
git_canonical_remote() {
  [ -n "$1" ] || return 1
  printf '%s' "$1" | perl -CS -ne '
    chomp; my $u=$_;
    $u =~ s/^\s+|\s+$//g;
    # git@host:owner/repo(.git)  scp 形态
    if    ($u =~ m{^git@([^:]+):(.+)$})                      { $u = "$1/$2"; }
    # ssh://[user@]host[:port]/owner/repo(.git)
    elsif ($u =~ m{^ssh://(?:[^@/]+@)?([^/]+?)(?::\d+)?/(.+)$}) { $u = "$1/$2"; }
    # (http|https|git|file)://[user@]host/owner/repo(.git)
    elsif ($u =~ m{^(?:https?|git|file)://(?:[^@/]+@)?([^/]+)/(.+)$}) { $u = "$1/$2"; }
    $u =~ s{^[^/:]+@}{};   # 再剥残余 user@host
    $u =~ s{\.git$}{}i;    # 去 .git 后缀
    $u =~ s{/+$}{};        # 去尾部斜杠
    print lc($u), "\n";
  '
}

# 从会话 jsonl 提取第一条 cwd(真实 origin 绝对路径);JSON 反义(把 \\ 还原)
# 用法: session_origin_cwd <files...>
session_origin_cwd() {
  perl -CS -ne '
    if (/"cwd":"((?:[^"\\]|\\.)*)"/) {
      my $s=$1;
      $s =~ s/\\\\/\\/g; $s =~ s/\\"/"/g; $s =~ s/\\n/\n/g; $s =~ s/\\t/\t/g;
      print $s; exit;
    }
  ' "$@"
}

# 找出 origin 仓库根 + 规范化 remote。cwd 在 origin 机真实存在。
# 用法: git_identity_of <cwd> ;输出两行 "<toplevel>\n<remote>"
git_identity_of() {
  local cwd="$1" tl ru
  [ -n "$cwd" ] || return 1
  tl="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)" || return 1
  ru="$(git -C "$tl" remote get-url origin 2>/dev/null)" || return 1
  ru="$(git_canonical_remote "$ru")" || return 1
  [ -n "$ru" ] || return 1
  printf '%s\n%s\n' "$tl" "$ru"
}

# ---------- 本机 checkout 索引(扫描 + 缓存) ----------
identity_roots() {
  if [ -n "${IDENTITY_ROOTS:-}" ]; then printf '%s\n' "${IDENTITY_ROOTS}"; return; fi
  printf '%s\n' "${HOME}"
  # 再带上可能存在的盘根:git-bash 是 /c /d,WSL 是 /mnt/c /mnt/d
  local p
  shopt -s nullglob 2>/dev/null
  for g in /[a-z] /[A-Z] /mnt/[a-z] /mnt/[A-Z]; do
    for p in $g; do
      [ -d "$p" ] && [ "$p" != "$HOME" ] && printf '%s\n' "$p"
    done
  done
  shopt -u nullglob 2>/dev/null
}

# 平铺扫描各根,输出 "<canonical_remote>\t<绝对路径>"(去重:同 remote 首见保留)
scan_identity() {
  local -A seen=()
  local root depth maxd gitdir cfg url r path p g
  for root in $(identity_roots); do
    depth="${IDENTITY_SCAN_DEPTH:-3}"
    maxd=$(( depth + 1 ))
    while IFS= read -r gitdir; do
      [ -d "$gitdir" ] || continue
      cfg="$gitdir/config"; [ -f "$cfg" ] || continue
      url="$(awk -v want='remote "origin"' '
        /^\[/              { sec=substr($0,2,length($0)-2) }
        sec==want && /^[ \t]*url[ \t]*=/ { sub(/^[^=]*=/,""); gsub(/^[ \t]+|[ \t]+$/,""); print; exit }
      ' "$cfg")"
      [ -n "$url" ] || continue
      r="$(git_canonical_remote "$url")" || continue
      [ -n "$r" ] || continue
      path="${gitdir%/.git}"; [ -n "$path" ] || continue
      if [ -z "${seen[$r]:-}" ]; then
        seen[$r]="$path"; printf '%s\t%s\n' "$r" "$path"
      fi
    done < <(find "$root" -maxdepth "$maxd" \
        \( -name node_modules -o -name _unclaimed -o -name .cache -o -name vendor \
           -o -name target -o -name .svn -o -name .hg -o -name __pycache__ \) -prune \
        -o -name .git -type d -print 2>/dev/null)
  done
}

# ---------- .identity 缓存读写 ----------
# 读: <cachefile> ;写:scan_identity > cachefile
identity_cache_rw() {
  if [ "$1" = "save" ]; then
    mkdir -p "$(dirname "$IDENTITY_CACHE_FILE")" 2>/dev/null
    scan_identity > "$IDENTITY_CACHE_FILE.tmp" 2>/dev/null
    mv "$IDENTITY_CACHE_FILE.tmp" "$IDENTITY_CACHE_FILE"
  else
    local r p
    while IFS=$'\t' read -r r p; do
      [ -n "$r" ] && [ -n "$p" ] && IDENT_CACHE[$r]="${IDENT_CACHE[$r]:-$p}"
    done < "$IDENTITY_CACHE_FILE"
  fi
}

# 建缓存:新鲜则 load,过期/空则重建;force=1 强制重建。均填充内存 IDENT_CACHE。
ensure_identity_cache() {
  local force="${1:-0}" ts now
  if [ "$force" = "1" ] || [ ! -s "$IDENTITY_CACHE_FILE" ]; then
    identity_cache_rw save
    identity_cache_rw load
    return
  fi
  ts="$(stat -c %Y "$IDENTITY_CACHE_FILE" 2>/dev/null || echo 0)"
  now="$(date +%s)"
  if [ $(( now - ts )) -gt "${IDENTITY_CACHE_TTL:-21600}" ]; then
    identity_cache_rw save
    identity_cache_rw load
  else
    identity_cache_rw load
  fi
}

identity_remote_of()    { local s="$1"; [ -f "$s/.identity" ] || return 1; sed -n 's/^remote=//p' "$s/.identity"; }
identity_toplevel_of()  { local s="$1"; [ -f "$s/.identity" ] || return 1; sed -n 's/^toplevel=//p' "$s/.identity"; }

# 目标编码:remote 在本机索引命中 -> cwd_encode(本地 checkout 路径);否则空
resolve_by_identity() {
  local sdir="$1" remote path
  remote="$(identity_remote_of "$sdir")" || return 1
  [ -n "$remote" ] || return 1
  path="${IDENT_CACHE[$remote]:-}"
  [ -n "$path" ] || return 1
  cwd_encode "$path"
}

# 拷贝落下时把 cwd 前缀 "cwd":"<from>" -> <to>(仅落地副本,不改共享仓)。
# from 为空 / to==from / 无 perl => 原样复制。
cwd_rewrite_copy() {
  local in="$1" out="$2" from="$3" to="$4"
  if [ -z "$from" ] || [ -z "$to" ] || [ "$from" = "$to" ] || ! command -v perl >/dev/null 2>&1; then
    cp -f "$in" "$out"; return
  fi
  REWRITE_FROM="$from" REWRITE_TO="$to" perl -CS -pe '
    my $from=$ENV{REWRITE_FROM}; my $to=$ENV{REWRITE_TO};
    my $needle = qq!"cwd":"$from!;
    my $i = index($_, $needle);
    if ($i >= 0) { substr($_, $i, length($needle), qq!"cwd":"$to!) }
  ' "$in" > "$out.$$" 2>/dev/null && mv "$out.$$" "$out" || { rm -f "$out.$$"; cp -f "$in" "$out"; }
}