#!/usr/bin/env perl
# =====================================================================
# transcript.pl — 把单条 Claude Code 会话 .jsonl 渲染成可读输出。
# 纯 perl + JSON::PP(都随 Git for Windows / Linux / macOS 的 perl 自带),
# 复用插件的跨平台承诺(零额外依赖)。只会读取,不改动文件。
#
# 用法:
#   transcript.pl <file.jsonl> [--format text|html] [--no-thinking] [--full]
#                 [--host H] [--sanitize yes|no]
#   transcript.pl --inventory <sessions_dir> [--json|--tsv] [--q TERM]
#                 [--host TERM] [--root-map src:dst]...
#
# --inventory 扫描一个 sessions/ 目录,汇总所有会话元信息(对齐表格 / tsv / json)。
# =====================================================================
use strict; use warnings;
use JSON::PP;
use Getopt::Long;
use Encode;
use open ':std', ':encoding(UTF-8)';    # STDIO 按 UTF-8;@ARGV 不归 :std 管,下方手动解码

our %opt;
GetOptions(
  'format=s'   => \$opt{format},
  'no-thinking'=> \$opt{'no-thinking'},
  'full'       => \$opt{full},
  'host=s'     => \$opt{host},
  'sanitize=s' => \$opt{sanitize},
  'inventory=s'=> \$opt{inventory},
  'json'       => \$opt{json},
  'tsv'        => \$opt{tsv},
  'q=s'        => \$opt{q},
  'host-f=s'   => \$opt{'host-f'},   # 与 --host 同名,留 --host 给 show 用
  'root-map=s' => sub { push @{$opt{'root-map'}}, $_[1] },
) or exit 2;

# @ARGV 是字节串,:std 不负责;按 UTF-8 解码,否则 CJK --q/--host-f 匹配不上
for my $k (qw(q host-f)) {
    $opt{$k} = decode('UTF-8', $opt{$k}) if defined $opt{$k};
}

if (defined $opt{inventory}) { inventory($opt{inventory}); exit 0; }

my $file = shift @ARGV or die "usage: transcript.pl <file.jsonl> [--format text|html] [...]\n";
my $format = $opt{format} || 'text';

my @rows = read_jsonl($file);
my $meta = meta_of(\@rows, $file);

if ($format eq 'html') { print render_html(\@rows, $meta); }
else                   { print render_text(\@rows, $meta); }
exit 0;

# ---------- 基础 ----------
sub read_jsonl {
    my ($f) = @_;
    open my $fh, '<:encoding(UTF-8)', $f or die "open $f: $!\n";
    my @rows;
    while (my $l = <$fh>) {
        chomp $l; next if $l =~ /^\s*$/;
        my $o = eval { decode_json($l) } or next;
        push @rows, $o;
    }
    close $fh;
    return @rows;
}

# 元信息 + 计数。 $dir = .source 所在目录(host/sanitize 用),可为 undef
sub meta_of {
    my ($rows, $file) = @_;
    my %m = (id=>undef, title=>undef, cost=>undef, first=>undef, last=>undef,
             nuser=>0, nassist=>0, ntool=>0, nthink=>0, cwd=>undef, host=>undef);
    for my $r (@$rows) {
        my $t = $r->{type} // next;
        my $ts = $r->{timestamp};
        $m{first} //= $ts; $m{last} = $ts if defined $ts;
        $m{id}    //= $r->{sessionId};
        if    ($t eq 'ai-title')   { $m{title} = $r->{aiTitle} if $r->{aiTitle}; }
        elsif ($t eq 'cost-state') { $m{cost}  = $r->{totalCostUSD} if defined $r->{totalCostUSD}; }
        elsif ($t eq 'user')       { $m{nuser}++; $m{cwd} //= $r->{cwd}; }
        elsif ($t eq 'assistant')  {
            $m{nassist}++;
            for my $b (@{ $r->{message}{content} // [] }) {
                next unless ref $b eq 'HASH';
                $m{ntool} ++ if $b->{type} eq 'tool_use';
                $m{nthink}++ if $b->{type} eq 'thinking';
            }
        }
    }
    if (defined $opt{host}) { $m{host} = $opt{host}; }
    elsif (defined $opt{'host-f'}) { $m{host} = $opt{'host-f'}; }
    else {
        # 尝试从同目录 .source 读 host
        my $dir = $file; $dir =~ s{/[^/]+$}{} or $dir='.';
        read_source_host($dir, \%m);
    }
    return \%m;
}

sub read_source_host {
    my ($dir, $m) = @_;
    open my $fh, '<', "$dir/.source" or return;
    while (my $l = <$fh>) {
        chomp $l;
        if ($l =~ /host=([^\s]+)/) { $m->{host} = $1; last; }
    }
    close $fh;
}

# ---------- 文本渲染 ----------
sub render_text {
    my ($rows, $m) = @_;
    my @out;
    push @out, "# ${$m}{id}";
    push @out, "项目:   " . ($m->{cwd} // '?');
    push @out, "标题:   " . ($m->{title} // '-');
    push @out, "时间:   " . (ts_str($m->{first}) // '?') . " ～ " . (ts_str($m->{last}) // '?');
    push @out, "host:   " . ($m->{host} // '?') . "   成本: \$" . (defined $m->{cost} ? sprintf('%.4f',$m->{cost}) : '?') .
               "   会话:{$m->{nuser}}/回复:{$m->{nassist}}/工具:{$m->{ntool}}";
    push @out, "-" x 60;
    for my $r (@$rows) {
        my $t = $r->{type};
        if ($t eq 'user') {
            my $msg = $r->{message};
            my $roles = ref $msg eq 'HASH' ? $msg->{content} : $msg;
            if (ref $roles eq 'ARRAY') {
                for my $b (@$roles) {
                    if ($b->{type} eq 'tool_result') { push @out, block_tool_result($b, $m); }
                    elsif ($b->{type} eq 'text')     { push @out, ">>> user\n" . $b->{text}; }
                }
            } elsif (ref $roles eq 'HASH' && $roles->{content}) {
                push @out, ">>> user\n" . $roles->{content};
            } elsif (!ref $roles) {
                push @out, ">>> user\n" . ($roles // '');
            }
        }
        elsif ($t eq 'assistant') {
            my $ts = "(" . (ts_str($r->{timestamp}) // '') . ")";
            push @out, ">>> assistant $ts";
            for my $b (@{ $r->{message}{content} // [] }) {
                next unless ref $b eq 'HASH';
                my $bt = $b->{type};
                if    ($bt eq 'text')    { push @out, $b->{text}; }
                elsif ($bt eq 'tool_use'){ push @out, "   [tool] " . ($b->{name}//'?') . " → " . trunc(to_s($b->{input})); }
                elsif ($bt eq 'thinking'){ show_thinking(\@out, $b->{thinking}); }
            }
        }
    }
    push @out, "-" x 60;
    return (join "\n", @out) . "\n";
}

sub show_thinking {
    my ($out, $txt) = @_;
    return if $opt{'no-thinking'};
    if ($opt{full}) { push @$out, "   [thinking]\n" . $txt; }
    else {
        my $n = defined $txt ? length($txt) : 0;
        push @$out, "   [thinking: $n 字符, --full 查看]";
    }
}

sub block_tool_result {
    my ($b, $m) = @_;
    my $err = $b->{is_error} ? " (is_error)" : "";
    my $content = ref $b->{content} eq 'ARRAY'
        ? join("\n", map { ref $_ eq 'HASH' ? (esc_txt($_->{text}) // '') . (ref $_->{content} ? one_line($_->{content}) : '') : (esc_txt($_) // '') } @{ $b->{content} })
        : ($b->{content} // '');
    $content = trunc($content) unless $opt{full};
    return "   [result$err] " . ($b->{tool_use_id}//'') . "\n      " . $content;
}

# ---------- HTML 渲染 ----------
sub esc { my $s = shift; defined($s) or return ''; $s =~ s/&/&amp;/g; $s =~ s/</&lt;/g; $s =~ s/>/&gt;/g; $s =~ s/"/&quot;/g; return $s; }
sub esc_txt { my $s=shift; return '' unless defined $s; $s =~ s/\x00//g; return $s; }

sub render_html {
    my ($rows, $m) = @_;
    my $host = esc($m->{host} // '?');
    my $title = esc($m->{title} // '(无标题)');
    my $html;
    $html = "<!DOCTYPE html><html><head><meta charset='utf-8'>"
          . "<title>" . esc(${$m}{id}) . "</title><style>"
          . "body{font-family:system-ui,-apple-system,Segoe UI,Roboto,sans-serif;margin:2em auto;max-width:900px;line-height:1.55;color:#1f2328;background:#fff;padding:0 1em}"
          . "h1{font-size:1.2em;border-bottom:1px solid #e1e4e8;padding-bottom:.4em;word-break:break-all}"
          . ".meta{color:#57606a;font-size:.85em;white-space:pre-wrap}"
          . ".msg{border:1px solid #e1e4e8;border-radius:8px;padding:.7em 1em;margin:.6em 0}"
          . ".u{border-left:4px solid #0969da;background:#f6f8fa}"
          . ".a{border-left:4px solid #2da44e;background:#f0fff4}"
          . ".lb{font-weight:600;font-size:.8em;color:#57606a;margin-bottom:.3em}"
          . "pre{white-space:pre-wrap;word-wrap:break-word;margin:.2em 0;font-family:ui-monospace,SFMono-Regular,Consolas,monospace;font-size:.85em}"
          . "details{border-top:1px dashed #d0d7de;margin-top:.6em;padding-top:.5em}"
          . "summary{cursor:pointer;font-size:.8em;color:#0969da}"
          . ".tool{background:#fafbfc;border-radius:6px;padding:.5em .7em;margin:.3em 0;font-size:.85em}"
          . ".tc{font-weight:600;color:#6e40c9}"
          . ".erno{color:#cf222e;font-weight:700}"
          . "</style></head><body>";
    $html .= "<h1>" . esc(${$m}{id}) . "</h1>";
    $html .= "<div class='meta'>项目 " . esc($m->{cwd}//'?') . "\n标题 $title"
           . "\n时间 " . (ts_str($m->{first})//'?') . " ～ " . (ts_str($m->{last})//'?')
           . "\nhost " . $host . " 成本 \$" . (defined $m->{cost}?sprintf('%.4f',$m->{cost}):'?')
           . "  会话:{$m->{nuser}} 回复:{$m->{nassist}} 工具:{$m->{ntool}}</div>";
    for my $r (@$rows) {
        my $t = $r->{type};
        if ($t eq 'user') {
            my $msg = $r->{message};
            my $roles = ref $msg eq 'HASH' ? $msg->{content} : $msg;
            if (ref $roles eq 'ARRAY') {
                for my $b (@$roles) {
                    if    ($b->{type} eq 'text')      { $html .= "<div class='msg u'><div class='lb'>user</div><pre>" . esc($b->{text}) . "</pre></div>"; }
                    elsif ($b->{type} eq 'tool_result'){ $html .= block_result_html($b); }
                }
            } elsif (defined $roles) {
                my $s = ref $roles eq 'HASH' ? $roles->{content} : $roles;
                $html .= "<div class='msg u'><div class='lb'>user</div><pre>" . esc($s) . "</pre></div>";
            }
        }
        elsif ($t eq 'assistant') {
            $html .= "<div class='msg a'><div class='lb'>assistant " . (ts_str($r->{timestamp})//'') . "</div>";
            my $first=1;
            for my $b (@{ $r->{message}{content} // [] }) {
                next unless ref $b eq 'HASH';
                my $bt = $b->{type};
                if    ($bt eq 'text')    { $html .= "<pre>" . esc($b->{text}) . "</pre>"; }
                elsif ($bt eq 'tool_use'){ $html .= tool_html($b); $first=0; }
                elsif ($bt eq 'thinking'){ $html .= thinking_html($b->{thinking}); }
            }
            $html .= "</div>";
        }
    }
    $html .= "</body></html>\n";
    return $html;
}

sub tool_html {
    my ($b) = @_;
    my $in = to_s($b->{input});
    $in = trunc($in) unless $opt{full};
    return "<div class='tool'><span class='tc'>tool</span> <b>" . esc($b->{name}//'?') . "</b><pre>" . esc($in) . "</pre></div>";
}

sub thinking_html {
    my ($txt) = @_;
    return '' if $opt{'no-thinking'};
    my $n = defined $txt ? length($txt) : 0;
    return "<details><summary>thinking ($n 字符)</summary><pre>" . esc($txt) . "</pre></details>";
}

sub block_result_html {
    my ($b) = @_;
    my $err = $b->{is_error} ? "<span class='erno'>(is_error)</span>" : "";
    my $content = ref $b->{content} eq 'ARRAY'
        ? join("\n", map { ref $_ eq 'HASH' ? (defined $_->{text} ? $_->{text} : '') . (ref $_->{content} ? one_line($_->{content}) : '') : $_ } @{ $b->{content} })
        : ($b->{content} // '');
    $content = trunc($content) unless $opt{full};
    return "<div class='tool'><span class='tc'>result</span> $err " . esc($b->{tool_use_id}//'') . "<pre>" . esc($content) . "</pre></div>";
}

# ---------- 目录清单 ----------
sub inventory {
    my ($dir) = @_;
    opendir my $dh, $dir or die "cannot open $dir: $!\n";
    my @entries;
    for my $d (sort readdir $dh) {
        next if $d =~ /^\./;
        my $path = "$dir/$d";
        next unless -d $path;
        opendir my $dh2, $path or next;
        my @files = sort grep { /\.jsonl$/ } readdir $dh2;
        closedir $dh2;
        for my $fn (@files) {
            my $f = "$path/$fn";
            my @rows = read_jsonl($f);
            my $m = meta_of(\@rows, $f);
            apply_filters($m, \@rows);
            push @entries, $m if $m->{keep};
        }
    }
    closedir $dh;
    if ($opt{json}) { print encode_json(\@entries), "\n"; }
    elsif ($opt{tsv}) { print_inventory_tsv(\@entries); }
    else            { print_inventory_table(\@entries); }
}

sub apply_filters {
    my ($m, $rows) = @_;
    $m->{keep} = 1;
    if (defined $opt{host} || defined $opt{'host-f'}) {
        my $h = defined $opt{'host-f'} ? $opt{'host-f'} : $opt{host};
        $m->{keep} = 0 if defined $m->{host} && $m->{host} ne $h;
    }
    if (defined $opt{q}) {
        my $q = lc $opt{q};
        $m->{keep} = 0 if lc($m->{id}//'') !~ /\Q$q\E/ && lc($m->{title}//'') !~ /\Q$q\E/;
    }
    # 根替换解码展示路径
    if (@{$opt{'root-map'} // []}) {
        my $c = $m->{cwd} // '';
        for my $rp (@{$opt{'root-map'}}) {
            my ($src,$dst) = split /:/, $rp, 2;
            $c =~ s/^\Q$src\E/$dst/ if defined $src && defined $dst && $c =~ /^\Q$src\E/;
        }
        $m->{proj} = $c;
        $m->{rawproj} = $m->{cwd};
    } else { $m->{proj} = $m->{cwd}; }
}

sub print_inventory_table {
    my ($entries) = @_;
    my @rows = map {
        [ $_->{id}, $_->{host}//'-', date_str($_->{first}), $_->{proj}//'?', m_title($_->{title}), $_->{cost}, $_->{nuser}, $_->{nassist}, $_->{ntool} ]
    } @$entries;
    my @widths = (36, 18, 17, 36, 44, 8, 5, 6, 7);
    my @hdr = ('sessionId','host','date','project','title','cost$','msg','rep','tool');
    print join('  ', map { pad_to($hdr[$_], $widths[$_]) } 0..$#hdr), "\n";
    print '-' x (146), "\n";
    for my $r (@rows) { print join('  ', map { pad_to($r->[$_], $widths[$_]) } 0..$#hdr), "\n"; }
}
sub pad_to {
    my ($c,$w) = @_;
    $c = '-' unless defined $c;
    $c = "$c";
    if (length($c) > $w) { $c = substr($c,0,$w-1) . '…'; }
    return sprintf("%-*s", $w, $c);
}

# 机器可读 TSV:id host first proj title cost nuser nassist ntool(供 view.sh export 组装索引)
sub print_inventory_tsv {
    my ($entries) = @_;
    for my $m (@$entries) {
        my $t = $m->{title} // '-';    $t =~ s/[\t\r\n]+/ /g;
        my $p = $m->{proj}  // '?';    $p =~ s/[\t\r\n]+/ /g;
        print join("\t", $m->{id}//'', $m->{host}//'-', $m->{first}//'', $p, $t,
                   (defined $m->{cost} ? $m->{cost} : '-'),
                   $m->{nuser}, $m->{nassist}, $m->{ntool}), "\n";
    }
}
sub m_title { my $t=shift; return '-' unless defined $t; $t =~ s/\s+/ /g; return (length($t)>40 ? substr($t,0,40).'...' : $t); }

# ---------- 工具 ----------
sub ts_str {
    my $s = shift; return undef unless defined $s;
    $s =~ s{[T].*}{}; return $s;
}
sub date_str {
    my $s = shift; return '-' unless defined $s;
    my ($y,$mo,$d,$h,$mi) = $s =~ /^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})/;
    return defined $y ? "$y-$mo-$d $h:$mi" : $s;
}
sub trunc { my $s = shift; my $n = 800; return '' unless defined $s; return $s if length($s) <= $n; return substr($s,0,$n) . "\n…[截断,用 --full 查看全文]"; }
sub one_line { my $v = shift; return '' unless defined $v; my $s = ref $v eq '' ? $v : (eval { decode_json($v) } // ''); $s = '' unless defined $s; $s =~ s/\s+/ /g; return substr($s,0,300); }
# 纯字符串化:ref(HASH/ARRAY) → JSON 文本;标量 → 原样
sub to_s { my $v = shift; return '' unless defined $v; return $v unless ref $v; return eval { JSON::PP->new->allow_nonref->encode($v) } // "$v"; }

# 让 GetOptions 兼容 --host-f(留给 --host 给 show)
{
    no strict 'refs';
}