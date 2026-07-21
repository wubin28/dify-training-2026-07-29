#!/usr/bin/env zsh
# run-eval.sh —— 规范问答智能体验收跑批（Dify 版）
#
# 用途：第 3 章（第三次培训·智能体）。把 questions.yaml 的 10 道题打给一个或
#      多个 Dify 聊天类应用（Chatflow / Agent），输出「版本 × 题目」对错矩阵。
#
# 这是整套备课脚本的核心杠杆：
#   手工点 = v0..v4 五个版本 × 10 题 = 50 次问答，且不可复现。
#   脚本跑 = 一条命令，出一张能直接投屏的矩阵。
#   那张矩阵就是排错专场最好的教具 —— 学员一眼看出
#   加了哪个要素、哪几道题从红转绿。
#
# 依赖：python3（标准库即可，不用 pip 装东西）
#
# 平台差异说明：本脚本是讲师（macOS + zsh）备课用。Windows 助教核对用
#   ../windows-pwsh/run-eval.ps1（同逻辑、同 Dify 端点）。
#
# 准备（Dify 鉴权模型：每个应用一把 API Key，不是一个令牌管多个应用）：
#   1) 每个版本在 Dify 里是一个独立的聊天类应用。打开应用 →「访问 API」→
#      生成/复制该应用的 API Key（形如 app-xxxxxxxxxxxxxxxx）。
#   2) 设置 API 基地址（默认本地备课环境）：
#        export DIFY_API_BASE='http://localhost/v1'      # 本地 dify-up.sh 起的实例
#      院内学员/助教改成院内 DIFY 地址，例如：
#        export DIFY_API_BASE='https://dify.院内域名/v1'
#   3) 把各版本的 app key 填进 apps.env（见下方模板），或用 --app 直接传。
#
# 用法：
#   export DIFY_API_BASE='http://localhost/v1'
#   ./run-eval.sh --app v0=app-xxx,v1=app-yyy,v2=app-zzz
#   ./run-eval.sh --apps-file apps.env --out ../eval/matrix-$(date +%m%d).md
#   ./run-eval.sh --versions v0,v1,v2,v3,v4 --apps-file apps.env
#
# apps.env 模板（每行 版本名=应用API_Key）：
#   v0=app-xxxxxxxxxxxxxxxx
#   v1=app-yyyyyyyyyyyyyyyy
#
# Dify 端点说明：聊天类应用用 POST {base}/chat-messages，response_mode=blocking
#   直接返回最终 answer，无需轮询（比旧的异步 API 简单）。首次跑通若返回 4xx，
#   多半是 base 地址少了 /v1，或 app key 贴错。

set -euo pipefail

SCRIPT_DIR=${0:A:h}
QUESTIONS="$SCRIPT_DIR/../questions.yaml"   # 题库在 scripts/ 根，两个系统的 runner 共用
APPS=""
APPS_FILE=""
OUT=""
VERSIONS=""
BASE_URL="${DIFY_API_BASE:-http://localhost/v1}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)        APPS="$2"; shift 2 ;;
    --apps-file)  APPS_FILE="$2"; shift 2 ;;
    --versions)   VERSIONS="$2"; shift 2 ;;
    --questions)  QUESTIONS="$2"; shift 2 ;;
    --out)        OUT="$2"; shift 2 ;;
    -h|--help)    sed -n '2,45p' "$0"; exit 0 ;;
    *) print -u2 "未知参数: $1"; exit 1 ;;
  esac
done

[[ ! -f "$QUESTIONS" ]] && { print -u2 "题库不存在: $QUESTIONS"; exit 1; }

if [[ -n "$APPS_FILE" ]]; then
  [[ ! -f "$APPS_FILE" ]] && { print -u2 "apps 文件不存在: $APPS_FILE"; exit 1; }
  APPS=$(grep -v '^\s*#' "$APPS_FILE" | grep -v '^\s*$' | paste -sd, -)
fi
[[ -z "$APPS" ]] && { print -u2 "用法: $0 --app v1=<app-key>[,v2=<app-key>...] | --apps-file apps.env"; exit 1; }

# --versions 过滤：只跑指定的版本子集（apps.env 里全填、按需挑几个跑）
[[ -n "$VERSIONS" ]] && APPS=$(print -r -- "$APPS" | tr ',' '\n' | grep -E "^(${VERSIONS//,/|})=" | paste -sd, -)
[[ -z "$APPS" ]] && { print -u2 "--versions 过滤后没剩下任何应用，检查版本名"; exit 1; }

[[ -n "$OUT" ]] && mkdir -p "${OUT:h}"

python3 - "$QUESTIONS" "$APPS" "$BASE_URL" "${OUT:-}" <<'PY'
import json, os, re, sys, urllib.request, urllib.error

qfile, apps_arg, base_url, out_path = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
base_url = base_url.rstrip('/')

# ---- 极简 YAML 读取（只认本题库的结构，不引第三方库）----
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
        'conversation_id': '',        # 每题开新会话，避免上一题记忆串味
    }
    req = urllib.request.Request(url, data=json.dumps(body).encode(), method='POST', headers={
        'Authorization': f'Bearer {app_key}',
        'Content-Type': 'application/json',
    })
    try:
        with urllib.request.urlopen(req, timeout=120) as r:  # Agent 应用会慢，别调小
            d = json.loads(r.read())
    except urllib.error.HTTPError as e:
        return f'[HTTP {e.code}] {e.read().decode()[:300]}'
    except Exception as e:
        return f'[调用异常] {e}'
    return (d.get('answer') or '').strip() or '[空答案]'

def judge(ans, q, markers):
    """返回 (符号, 理由)。判定规则直接对应大纲验收线。"""
    said_nf = any(p in ans for p in markers['not_found_phrases'])
    has_article = bool(re.search(r'\d+\.\d+(\.\d+)?', ans))

    if q['expect'] == 'not_found':
        if said_nf and not has_article:
            return '✅', '正确拒答'
        if has_article:
            return '🔥', '编造条文 —— 不合格'      # 底线破防，单独标红
        return '❌', '未明确拒答'

    # expect == answer
    if said_nf:
        return '❌', '该答的没答出来（召回没命中）'
    missing = [c for c in q['cite_must'] if c not in ans]
    if missing:
        return '⚠️', f'答了但缺出处/关键点: {",".join(missing)}'
    return '✅', '答对且带出处'

# ---- 主流程 ----
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

# ---- 输出矩阵 ----
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
    # 大纲：8 道答对且带出处 + 2 道陷阱题明确拒答 + 零编造
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
PY
