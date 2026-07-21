#!/usr/bin/env pwsh
# run-eval.ps1 —— 规范问答智能体验收跑批（Dify 版 / Windows 11 + PowerShell 7）
#
# 与 ../macos-zsh/run-eval.sh 逻辑等价、打同一个 Dify 端点。用途：第 3 章
# （第三次培训·智能体）。把 questions.yaml 的 10 道题打给一个或多个 Dify
# 聊天类应用（Chatflow / Agent），输出「版本 × 题目」对错矩阵。
#
# 说明：新大纲里学员几乎纯浏览器操作、不碰命令行。此 PS7 版主要给讲师/助教在
# Windows 上核对备课产物、跑验收矩阵用。
#
# 依赖：python3（标准库即可）
#
# 准备（Dify 鉴权：每个应用一把 API Key）：
#   1) 每个版本在 Dify 里是一个独立的聊天类应用。打开应用 →「访问 API」→
#      复制该应用的 API Key（形如 app-xxxxxxxxxxxxxxxx）。
#   2) 设置 API 基地址（默认本地备课环境）：
#        $env:DIFY_API_BASE = 'http://localhost/v1'
#      院内学员/助教改成院内 DIFY 地址，例如：
#        $env:DIFY_API_BASE = 'https://dify.院内域名/v1'
#   3) 把各版本 app key 填进 apps.env（每行 版本名=app-key），或用 -App 直接传。
#
# 用法：
#   $env:DIFY_API_BASE = 'http://localhost/v1'
#   ./run-eval.ps1 -App "v0=app-xxx,v1=app-yyy,v2=app-zzz"
#   ./run-eval.ps1 -AppsFile apps.env -Out ..\eval\matrix.md
#   ./run-eval.ps1 -Versions "v0,v1,v2,v3,v4" -AppsFile apps.env

[CmdletBinding()]
param(
    [string]$App = "",
    [string]$AppsFile = "",
    [string]$Versions = "",
    [string]$Questions = "",
    [string]$Out = ""
)

$ErrorActionPreference = 'Stop'

# 题库在 scripts/ 根，两个系统的 runner 共用
if (-not $Questions) { $Questions = Join-Path $PSScriptRoot "..\questions.yaml" }
$baseUrl = if ($env:DIFY_API_BASE) { $env:DIFY_API_BASE } else { 'http://localhost/v1' }

if (-not (Test-Path -PathType Leaf $Questions)) { Write-Error "题库不存在: $Questions"; exit 1 }

if ($AppsFile) {
    if (-not (Test-Path -PathType Leaf $AppsFile)) { Write-Error "apps 文件不存在: $AppsFile"; exit 1 }
    $App = (Get-Content $AppsFile |
            Where-Object { $_ -notmatch '^\s*#' -and $_ -match '\S' }) -join ','
}
if (-not $App) { Write-Error "用法: -App v1=<app-key>[,v2=...] 或 -AppsFile apps.env"; exit 1 }

# -Versions 过滤：只跑指定的版本子集
if ($Versions) {
    $want = $Versions -split ','
    $App = ($App -split ',' | Where-Object {
        $name = ($_ -split '=')[0]; $want -contains $name
    }) -join ','
    if (-not $App) { Write-Error "-Versions 过滤后没剩下任何应用，检查版本名"; exit 1 }
}

if ($Out) {
    $outDir = Split-Path -Parent $Out
    if ($outDir) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }
}

$py = @'
import json, os, re, sys, urllib.request, urllib.error

qfile, apps_arg, base_url, out_path = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
base_url = base_url.rstrip('/')

def load_questions(path):
    qs, markers = [], {'not_found_phrases': [], 'fabrication_signals': []}
    cur, section, key = None, None, None
    for raw in open(path, encoding='utf-8'):
        line = raw.rstrip('\n')
        if not line.strip() or line.lstrip().startswith('#'):
            continue
        if line.startswith('questions:'):
            section = 'q'; continue
        if line.startswith('verdict_markers:'):
            section = 'm'; continue
        if section == 'q':
            m = re.match(r'\s*-\s*id:\s*(\S+)', line)
            if m:
                cur = {'id': m.group(1), 'cite_must': []}
                qs.append(cur); continue
            if cur is None: continue
            m = re.match(r'\s+ask:\s*"(.*)"\s*$', line)
            if m: cur['ask'] = m.group(1); continue
            m = re.match(r'\s+expect:\s*(\S+)', line)
            if m: cur['expect'] = m.group(1); continue
            m = re.match(r'\s+cite_must:\s*\[(.*)\]', line)
            if m:
                cur['cite_must'] = [s.strip().strip('"') for s in m.group(1).split(',') if s.strip()]
                continue
        if section == 'm':
            m = re.match(r'\s{2}(\w+):\s*$', line)
            if m: key = m.group(1); continue
            m = re.match(r'\s+-\s*"(.*)"\s*$', line)
            if m and key in markers: markers[key].append(m.group(1))
    return qs, markers

def ask_app(app_key, question, user='eval-runner'):
    """Dify 聊天类应用：POST /chat-messages（blocking），直接取 answer。"""
    url = f'{base_url}/chat-messages'
    body = {
        'inputs': {},
        'query': question,
        'response_mode': 'blocking',
        'user': user,
        'conversation_id': '',
    }
    req = urllib.request.Request(url, data=json.dumps(body).encode(), method='POST', headers={
        'Authorization': f'Bearer {app_key}',
        'Content-Type': 'application/json',
    })
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            d = json.loads(r.read())
    except urllib.error.HTTPError as e:
        return f'[HTTP {e.code}] {e.read().decode()[:300]}'
    except Exception as e:
        return f'[调用异常] {e}'
    return (d.get('answer') or '').strip() or '[空答案]'

def judge(ans, q, markers):
    said_nf = any(p in ans for p in markers['not_found_phrases'])
    has_article = bool(re.search(r'\d+\.\d+(\.\d+)?', ans))
    if q['expect'] == 'not_found':
        if said_nf and not has_article:
            return '✅', '正确拒答'
        if has_article:
            return '🔥', '编造条文 —— 不合格'
        return '❌', '未明确拒答'
    if said_nf:
        return '❌', '该答的没答出来（召回没命中）'
    missing = [c for c in q['cite_must'] if c not in ans]
    if missing:
        return '⚠️', f'答了但缺出处/关键点: {",".join(missing)}'
    return '✅', '答对且带出处'

questions, markers = load_questions(qfile)
apps = []
for pair in apps_arg.split(','):
    name, _, key = pair.partition('=')
    if not key:
        print(f'跳过格式错误的 app 参数: {pair}', file=sys.stderr); continue
    apps.append((name.strip(), key.strip()))

print(f'API 基地址：{base_url}')
print(f'题库 {len(questions)} 题 × 应用 {len(apps)} 个 = {len(questions)*len(apps)} 次调用\n')

results, raw_log = {}, []
for name, key in apps:
    print(f'--- {name} ({key[:12]}…) ---')
    for q in questions:
        ans = ask_app(key, q['ask'])
        sym, why = judge(ans, q, markers)
        results[(name, q['id'])] = (sym, why)
        raw_log.append({'app': name, 'qid': q['id'], 'ask': q['ask'],
                        'expect': q['expect'], 'verdict': sym, 'why': why, 'answer': ans})
        print(f'  {q["id"]} {sym} {why}')
    print()

lines = ['# 规范问答智能体验收矩阵（Dify）', '',
         f'API 基地址：{base_url}', '',
         '图例：✅ 合格　⚠️ 答对但缺出处　❌ 未命中/未拒答　🔥 **编造 —— 一票否决**', '']
head = '| 题号 | 期望 | ' + ' | '.join(n for n, _ in apps) + ' |'
sep  = '|---|---|' + '---|' * len(apps)
lines += [head, sep]
for q in questions:
    row = [q['id'], '拒答' if q['expect'] == 'not_found' else '作答']
    row += [results[(n, q['id'])][0] for n, _ in apps]
    lines.append('| ' + ' | '.join(row) + ' |')

lines += ['', '## 各版本合格率', '', '| 版本 | ✅ | ⚠️ | ❌ | 🔥 | 大纲验收线 |', '|---|---|---|---|---|---|']
for n, _ in apps:
    syms = [results[(n, q['id'])][0] for q in questions]
    c = {s: syms.count(s) for s in ('✅', '⚠️', '❌', '🔥')}
    passed = '通过' if (c['✅'] >= 10 and c['🔥'] == 0) else ('不合格（有编造）' if c['🔥'] else '未达线')
    lines.append(f'| {n} | {c["✅"]} | {c["⚠️"]} | {c["❌"]} | {c["🔥"]} | {passed} |')

report = '\n'.join(lines) + '\n'
print(report)

if out_path:
    open(out_path, 'w', encoding='utf-8').write(report)
    log_path = re.sub(r'\.md$', '', out_path) + '-raw.json'
    json.dump(raw_log, open(log_path, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
    print(f'矩阵 → {out_path}\n原始答案 → {log_path}')
    print('（原始答案 json 是排错专场的素材：答错时先看它到底召回了什么）')
'@

$py | & python3 - $Questions $App $baseUrl $Out
exit $LASTEXITCODE
