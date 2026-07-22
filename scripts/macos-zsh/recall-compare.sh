#!/usr/bin/env zsh
# recall-compare.sh —— 知识库 A/B 召回命中对比 (Dify v1.11.2 hit-testing API)
# 用法:
#   export DIFY_API_BASE='http://localhost/v1'
#   export DIFY_KB_KEY='dataset-xxxx'      # 知识库 API 密钥(非 app 密钥)
#   ./recall-compare.sh --a-dataset <A-UUID> --b-dataset <B-UUID> --out ../../eval/recall-ab-matrix.md
set -euo pipefail

DIFY_API_BASE="${DIFY_API_BASE:-http://localhost/v1}"
KB_KEY="${DIFY_KB_KEY:-}"
A_DATASET=""; B_DATASET=""
QUESTIONS="../questions.yaml"          # 脚本在 macos-zsh/ 下，题库在 scripts/ 根
OUT="../../eval/recall-ab-matrix.md"
TOP_K=3
METHOD="semantic_search"              # 可选 hybrid_search(需权重/rerank)

while [[ $# -gt 0 ]]; do
  case "$1" in
    --a-dataset) A_DATASET="$2"; shift 2;;
    --b-dataset) B_DATASET="$2"; shift 2;;
    --key)       KB_KEY="$2"; shift 2;;
    --questions) QUESTIONS="$2"; shift 2;;
    --out)       OUT="$2"; shift 2;;
    --top-k)     TOP_K="$2"; shift 2;;
    --method)    METHOD="$2"; shift 2;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done

[[ -n "$A_DATASET" && -n "$B_DATASET" && -n "$KB_KEY" ]] \
  || { echo "缺参数: 需要 --a-dataset / --b-dataset / 以及 DIFY_KB_KEY(或 --key)"; exit 2; }

python3 - "$DIFY_API_BASE" "$A_DATASET" "$B_DATASET" "$KB_KEY" "$QUESTIONS" "$OUT" "$TOP_K" "$METHOD" <<'PY'
import sys, os, re, json, urllib.request, urllib.error
base, a_ds, b_ds, key, qfile, out, top_k, method = sys.argv[1:9]
top_k = int(top_k)

# ---- 极简 questions.yaml 解析(只取 id/ask/expect/cite_must) ----
qs=[]; cur=None
for raw in open(qfile, encoding='utf-8'):
    s=raw.strip()
    m=re.match(r'-\s+id:\s*(\S+)', s)
    if m:
        cur={'id':m.group(1),'ask':'','expect':'','cite':[]}; qs.append(cur); continue
    if cur is None: continue
    if s.startswith('ask:'):        cur['ask']=s[4:].strip().strip('"')
    elif s.startswith('expect:'):   cur['expect']=s[7:].strip()
    elif s.startswith('cite_must:'):
        v=s[len('cite_must:'):].strip()
        try: cur['cite']=json.loads(v)
        except Exception: cur['cite']=[]
    elif s.startswith('verdict_markers'): break

def hit(ds, query):
    url=f"{base}/datasets/{ds}/hit-testing"
    body=json.dumps({"query":query,"retrieval_model":{
        "search_method":method,"reranking_enable":False,
        "reranking_model":{"reranking_provider_name":"","reranking_model_name":""},
        "weights":None,"top_k":top_k,
        "score_threshold_enabled":False,"score_threshold":0}}).encode('utf-8')
    req=urllib.request.Request(url, data=body, method='POST',
        headers={"Authorization":f"Bearer {key}","Content-Type":"application/json"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return json.loads(r.read().decode('utf-8'))
    except urllib.error.HTTPError as e:
        print(f"[HTTP {e.code}] ds={ds} q={query!r} -> {e.read().decode('utf-8')[:200]}", file=sys.stderr)
        return {"records":[]}

def summ(resp):
    out=[]
    for rec in resp.get('records',[]):
        seg=rec.get('segment',{}) or {}
        doc=(seg.get('document') or {}).get('name','?')
        out.append({'doc':doc,'score':round(rec.get('score',0) or 0,3),
                    'content':seg.get('content','') or ''})
    return out

rows=[]; raw={}
for q in qs:
    ra=summ(hit(a_ds,q['ask'])); rb=summ(hit(b_ds,q['ask']))
    raw[q['id']]={'ask':q['ask'],'A':ra,'B':rb}
    def cite(recs):
        if not q['cite']: return '—'
        blob=' '.join(x['content'] for x in recs)
        return '✓' if all(c in blob for c in q['cite']) else '✗'
    def top(recs): return (recs[0]['doc'], recs[0]['score']) if recs else ('（无命中）','-')
    ad,asc=top(ra); bd,bsc=top(rb)
    rows.append((q['id'],q['expect'],'/'.join(q['cite']) or '—',ad,asc,cite(ra),bd,bsc,cite(rb)))

os.makedirs(os.path.dirname(out) or '.', exist_ok=True)
with open(out,'w',encoding='utf-8') as f:
    f.write("# 知识库 A/B 召回命中对比矩阵\n\n")
    f.write(f"- 检索方式 `{method}`  top_k=`{top_k}`\n")
    f.write(f"- A(按条文切) dataset `{a_ds}`\n- B(按500字切) dataset `{b_ds}`\n\n")
    f.write("| ID | 期望 | 需含出处/值 | A顶命中 | A分 | A含? | B顶命中 | B分 | B含? |\n")
    f.write("|----|------|------------|---------|-----|------|---------|-----|------|\n")
    for r in rows: f.write("| "+" | ".join(str(x) for x in r)+" |\n")
with open(out.replace('.md','-raw.json'),'w',encoding='utf-8') as f:
    json.dump(raw,f,ensure_ascii=False,indent=2)

na=sum(1 for r in rows if r[5]=='✓'); nb=sum(1 for r in rows if r[8]=='✓')
print(f"A 命中含出处/值: {na}/{len(rows)}   B: {nb}/{len(rows)}")
print(f"写出: {out}")
print(f"原始召回: {out.replace('.md','-raw.json')}")
PY