#!/usr/bin/env zsh
# run-eval.sh —— 规范问答智能体验收跑批
#
# 用途：第 8–13 章。把 questions.yaml 的 10 道题打给一个或多个扣子 bot，
#      输出「版本 × 题目」对错矩阵（markdown 表）。
#
# 这是整套备课脚本的核心杠杆：
#   手工点 = v0..v5 六个版本 × 10 题 = 60 次问答，且不可复现。
#   脚本跑 = 一条命令，出一张能直接投屏的矩阵。
#   那张矩阵就是第 10 章排错专场最好的教具 —— 学员一眼看出
#   加了哪个要素、哪几道题从红转绿。
#
# 依赖：python3（标准库即可，不用 pip 装东西）
#
# 准备：
#   1) 扣子个人访问令牌（PAT）：扣子控制台 →【?扣子:PAT申请入口，预期在右上角头像→「API 授权」或「个人访问令牌」】
#   2) export COZE_PAT='pat_xxxxxxxx'
#   3) 把各版本 bot_id 填进 bots.env（见下方模板），或用 --bot 直接传
#
# 用法：
#   export COZE_PAT='pat_xxx'
#   ./run-eval.sh --bot v0=7412...,v1=7413...,v2=7414...
#   ./run-eval.sh --bots-file bots.env --out ../eval/matrix-$(date +%m%d).md
#
# bots.env 模板（每行 版本名=bot_id）：
#   v0=7412345678901234567
#   v1=7412345678901234568
#
# 【?扣子:API】以下 endpoint 按扣子 v3 对话 API 写就（api.coze.cn/v3/chat，
#   异步：发起 → 轮询 retrieve → 拉 message/list）。你第 9 章首次跑通时，
#   若返回 4xx，对照扣子开放平台文档回填真实路径/字段，并把这一行标记划掉。

set -euo pipefail

SCRIPT_DIR=${0:A:h}
QUESTIONS="$SCRIPT_DIR/questions.yaml"
BOTS=""
BOTS_FILE=""
OUT=""
BASE_URL="${COZE_BASE_URL:-https://api.coze.cn}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bot)        BOTS="$2"; shift 2 ;;
    --bots-file)  BOTS_FILE="$2"; shift 2 ;;
    --questions)  QUESTIONS="$2"; shift 2 ;;
    --out)        OUT="$2"; shift 2 ;;
    -h|--help)    sed -n '2,32p' "$0"; exit 0 ;;
    *) print -u2 "未知参数: $1"; exit 1 ;;
  esac
done

[[ -z "${COZE_PAT:-}" ]] && { print -u2 "缺 COZE_PAT。先跑: export COZE_PAT='pat_xxx'"; exit 1; }
[[ ! -f "$QUESTIONS" ]] && { print -u2 "题库不存在: $QUESTIONS"; exit 1; }

if [[ -n "$BOTS_FILE" ]]; then
  [[ ! -f "$BOTS_FILE" ]] && { print -u2 "bots 文件不存在: $BOTS_FILE"; exit 1; }
  BOTS=$(grep -v '^\s*#' "$BOTS_FILE" | grep -v '^\s*$' | paste -sd, -)
fi
[[ -z "$BOTS" ]] && { print -u2 "用法: $0 --bot v1=<bot_id>[,v2=<bot_id>...] | --bots-file bots.env"; exit 1; }

[[ -n "$OUT" ]] && mkdir -p "${OUT:h}"

python3 - "$QUESTIONS" "$BOTS" "$BASE_URL" "${OUT:-}" <<'PY'
import json, os, re, sys, time, urllib.request, urllib.error

qfile, bots_arg, base_url, out_path = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
PAT = os.environ['COZE_PAT']

# ---- 极简 YAML 读取（只认本题库的结构，不引第三方库）----
def load_questions(path):
    qs, markers = [], {'not_found_phrases': [], 'fabrication_signals': []}
    cur, section = None, None
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

def api(method, path, body=None):
    url = f'{base_url}{path}'
    data = json.dumps(body).encode() if body else None
    req = urllib.request.Request(url, data=data, method=method, headers={
        'Authorization': f'Bearer {PAT}',
        'Content-Type': 'application/json',
    })
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        raise RuntimeError(f'HTTP {e.code} {path}\n{e.read().decode()[:400]}')

def ask_bot(bot_id, question, user='eval-runner'):
    """发起对话 → 轮询完成 → 取 assistant 的最终答案。"""
    r = api('POST', '/v3/chat', {
        'bot_id': bot_id, 'user_id': user, 'stream': False,
        'auto_save_history': True,
        'additional_messages': [{'role': 'user', 'content': question, 'content_type': 'text'}],
    })
    d = r.get('data') or {}
    chat_id, conv_id = d.get('id'), d.get('conversation_id')
    if not chat_id:
        raise RuntimeError(f'发起对话没拿到 chat_id，原始返回：{json.dumps(r, ensure_ascii=False)[:300]}')

    for _ in range(60):  # 最多等 ~3 分钟。挂 MCP 工具的 v4 会明显变慢，别调小。
        time.sleep(3)
        s = api('GET', f'/v3/chat/retrieve?chat_id={chat_id}&conversation_id={conv_id}')
        st = (s.get('data') or {}).get('status')
        if st == 'completed':
            break
        if st in ('failed', 'requires_action'):
            return f'[对话状态 {st}] {json.dumps(s.get("data"), ensure_ascii=False)[:200]}'
    else:
        return '[超时未完成]'

    msgs = api('GET', f'/v3/chat/message/list?chat_id={chat_id}&conversation_id={conv_id}')
    parts = [m.get('content', '') for m in (msgs.get('data') or [])
             if m.get('role') == 'assistant' and m.get('type') == 'answer']
    return '\n'.join(parts).strip() or '[空答案]'

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
bots = []
for pair in bots_arg.split(','):
    name, _, bid = pair.partition('=')
    if not bid:
        print(f'跳过格式错误的 bot 参数: {pair}', file=sys.stderr); continue
    bots.append((name.strip(), bid.strip()))

print(f'题库 {len(questions)} 题 × bot {len(bots)} 个 = {len(questions)*len(bots)} 次调用\n')

results, raw_log = {}, []
for name, bid in bots:
    print(f'--- {name} ({bid}) ---')
    for q in questions:
        try:
            ans = ask_bot(bid, q['ask'])
        except Exception as e:
            ans = f'[调用异常] {e}'
        sym, why = judge(ans, q, markers)
        results[(name, q['id'])] = (sym, why)
        raw_log.append({'bot': name, 'qid': q['id'], 'ask': q['ask'],
                        'expect': q['expect'], 'verdict': sym, 'why': why, 'answer': ans})
        print(f'  {q["id"]} {sym} {why}')
    print()

# ---- 输出矩阵 ----
lines = ['# 规范问答智能体验收矩阵', '',
         f'生成时间：{time.strftime("%Y-%m-%d %H:%M")}　题库：{os.path.basename(qfile)}', '',
         '图例：✅ 合格　⚠️ 答对但缺出处　❌ 未命中/未拒答　🔥 **编造 —— 一票否决**', '']
head = '| 题号 | 期望 | ' + ' | '.join(n for n, _ in bots) + ' |'
sep  = '|---|---|' + '---|' * len(bots)
lines += [head, sep]
for q in questions:
    row = [q['id'], '拒答' if q['expect'] == 'not_found' else '作答']
    row += [results[(n, q['id'])][0] for n, _ in bots]
    lines.append('| ' + ' | '.join(row) + ' |')

lines += ['', '## 各版本合格率', '', '| 版本 | ✅ | ⚠️ | ❌ | 🔥 | 大纲验收线 |', '|---|---|---|---|---|---|']
for n, _ in bots:
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
