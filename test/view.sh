#!/usr/bin/env bash
# =====================================================================
# 会话浏览器(view.sh + transcript.pl)单元测试。
# 造一条合成 transcript(含 user/assistant text/thinking/tool_use/tool_result/
# cost-state/ai-title/.source),验证 list/show/export/筛选。
# 依赖 bash + perl(Git for Windows 内置)。
# 用法: bash test/view.sh
# =====================================================================
set -uo pipefail

S="$(cd "$(dirname "${BASH_SOURCE[0]}")/../plugins/session-sync" && pwd)"
SIM="$(mktemp -d)"; trap 'rm -rf "$SIM"' EXIT
SHARE="${SIM}/share/sessions/enc-day"
mkdir -p "${SHARE}"
# 指向测试专用 settings,避免读到真实 ~/.config/session-sync/settings.sh
CONF="${SIM}/settings.sh"
printf 'SHARE_ROOT="%s/share"\n' "${SIM}" > "${CONF}"
V(){ SESSION_SYNC_CONF="${CONF}" bash "${VIEW}" "$@"; }

ID="11111111-2222-4333-8444-555555555555"
SRC="${SHARE}/${ID}.jsonl"

# 用 perl 生成一条合成 transcript(.source 记录 host + sanitize 标记)
perl -e '
  use strict; use warnings; use JSON::PP;
  my $id = shift;
  my $src = shift;
  open my $f, ">", $src or die $!;    # 脚本字面量已是 UTF-8 字节(无 use utf8),写原始字节,勿再 :encoding 二次编码
  my $t = "2026-09-17T09:00:00.000Z";
  sub L {
    my ($type, $ref) = @_;
    my $row = { type=>$type, sessionId=>$id, timestamp=>$t, cwd=>"/home/fengye/proj", %$ref };
    print $f encode_json($row), "\n";
  }
  L("user",  { message=>{user => {text => "你好,请帮我看看这段代码"}} });
  L("assistant", { message=>{role=>"assistant", content=>[ {type=>"thinking", thinking=>"内部思考台词SECRET"},
      {type=>"text", text=>"这是正文文本UNIQUEBODY"},
      {type=>"tool_use", id=>"t1", name=>"Bash", input=>{command=>"echo hi"} }]} });
  L("user",  { message=>{content=>[ {type=>"tool_result", tool_use_id=>"t1", is_error=>0, content=>"工具返回OK"} ]} });
  L("ai-title",  { aiTitle=>"会话本地存储CJK" });
  L("user",  { cwd=>"/home/fengye/proj" });
  close $f;
' "$ID" "$SRC" >/dev/null
printf 'host=%s date=2026-09-17 sanitize=0\n' "$HOSTNAME" > "${SHARE}/.source"

VIEW="${S}/scripts/view.sh"
PASS=0; FAIL=0
ok(){  echo "  ✓ $1"; PASS=$((PASS+1)); }
bad(){ echo "  ✗ FAIL: $1"; FAIL=$((FAIL+1)); }

# 1. list 元信息正确(含 CJK 标题)
out="$(V list)"
echo "${out}" | grep -q "${ID}" && ok "list 列出合成会话"      || bad "list 未列出合成会话"
echo "${out}" | grep -q "会话本地存储CJK" && ok "list 显示 CJK 标题" || bad "list 标题缺 CJK"

# 2. show 文本:含正文,不含 thinking 台词
txt="$(V show "${ID}")"
echo "${txt}" | grep -q "UNIQUEBODY" && ok "show 含正文文本"      || bad "show 缺正文文本"
echo "${txt}" | grep -qi "SECRET"     && bad "show 泄漏 thinking 台词" || ok "show 默认收起 thinking"

# 3. --no-thinking 明确不含 thinking;--full 含工具输入
nt="$(V show "${ID}" --no-thinking)"
echo "${nt}" | grep -q "SECRET" && bad "--no-thinking 仍含 thinking" || ok "--no-thinking 不含 thinking"
V show "${ID}" --full 2>/dev/null | grep -q "echo hi" \
  && ok "--full 显示工具 input" || bad "--full 未显示工具 input"

# 4. show --html 出单页含正文
html="$(V show "${ID}" --html)"
echo "${html}" | grep -qi "<html" && ok "show --html 出 HTML"        || bad "show --html 无 <html>"
echo "${html}" | grep -q "UNIQUEBODY" && ok "HTML 含正文"             || bad "HTML 缺正文"

# 5. export 生成 index.html + 每会话一个 html
outd="${SIM}/export"
V export "${outd}" >/dev/null
[ -f "${outd}/index.html" ] && [ -f "${outd}/${ID}.html" ] \
  && ok "export 生成 index + 会话 html" || bad "export 缺文件"
grep -qi "UNIQUEBODY" "${outd}/${ID}.html" && ok "导出 html 含正文" || bad "导出 html 缺正文"

# 6. CJK --q 筛选能命中;不存在的词返回空
hit="$(V list --q 存储)"
echo "${hit}" | grep -q "${ID}" && ok "--q CJK 命中标题" || bad "--q CJK 未命中"
miss="$(V list --q 不存在词XYZ)"
! echo "${miss}" | grep -q "${ID}" && ok "--q 无匹配返回空" || bad "--q 无匹配仍返回行"

# 7. --json 输出合法(用 perl 校验首行 JSON)
V list --json | head -1 \
  | perl -MJSON::PP -e 'my $d = <STDIN>; chomp $d; eval { decode_json($d) } or die "bad json"; print "ok"' 2>/dev/null \
  | grep -q ok && ok "list --json 合法" || bad "list --json 非法"

echo
echo "── 视图测试: PASS=${PASS} FAIL=${FAIL} ──"
[ "${FAIL}" -eq 0 ] || exit 1
echo "ALL PASSED"