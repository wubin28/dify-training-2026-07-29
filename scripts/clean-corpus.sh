#!/usr/bin/env zsh
# clean-corpus.sh —— 公开国标 PDF → 干净可入库文本
#
# 用途：第 6、7 章。把讲师侧兜底语料（公开国标/图集 PDF）洗成扣子/Dify
#      能正确切分的 md 片段。
#
# 依赖：brew install poppler
#
# 用法：
#   ./clean-corpus.sh --in ../raw/pdf --out ../corpus/by-article --by-article
#   ./clean-corpus.sh --in ../raw/pdf --out ../corpus/by-500  --by-chars 500
#
# 两种切分粒度是第 8 章「切分粒度 A/B 实验」的两个实验组。
# 同一批 PDF 跑两次，得到两个语料目录，分别灌进两个知识库对比召回质量。

set -euo pipefail

IN_DIR=""
OUT_DIR=""
MODE="by-article"
CHARS=500

while [[ $# -gt 0 ]]; do
  case "$1" in
    --in)        IN_DIR="$2"; shift 2 ;;
    --out)       OUT_DIR="$2"; shift 2 ;;
    --by-article) MODE="by-article"; shift ;;
    --by-chars)  MODE="by-chars"; CHARS="$2"; shift 2 ;;
    -h|--help)   sed -n '2,20p' "$0"; exit 0 ;;
    *) print -u2 "未知参数: $1"; exit 1 ;;
  esac
done

[[ -z "$IN_DIR" || -z "$OUT_DIR" ]] && { print -u2 "用法: $0 --in <pdf目录> --out <输出目录> [--by-article | --by-chars N]"; exit 1; }
[[ ! -d "$IN_DIR" ]] && { print -u2 "输入目录不存在: $IN_DIR"; exit 1; }

command -v pdftotext >/dev/null || { print -u2 "缺 pdftotext。先跑: brew install poppler"; exit 1; }

mkdir -p "$OUT_DIR"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

print "=== 1/3 提取文本 ==="
count=0
for pdf in "$IN_DIR"/**/*.pdf(N); do
  # 规范化文件名：空格→连字符，去中文括号，去全角符号
  base=$(basename "$pdf" .pdf)
  slug=$(print -r -- "$base" \
    | sed -e 's/[[:space:]]\{1,\}/-/g' \
          -e 's/[（）()《》【】]//g' \
          -e 's/-\{2,\}/-/g' \
          -e 's/^-//' -e 's/-$//')

  # -layout 保留版面，表格类国标条文不会被拆成乱序
  pdftotext -layout -enc UTF-8 "$pdf" "$WORK/$slug.txt" 2>/dev/null || {
    print -u2 "  !! 解析失败，跳过: $base"
    continue
  }
  count=$((count+1))
  print "  ok: $slug"
done
print "提取完成: $count 份"

[[ $count -eq 0 ]] && { print -u2 "没有任何 PDF 被成功解析。检查输入目录。"; exit 1; }

print "=== 2/3 清洗噪声 ==="
for txt in "$WORK"/*.txt(N); do
  # 去页眉页脚常见噪声：孤立页码行、"GB 50016-2014" 重复页眉、连续空行
  sed -E \
    -e '/^[[:space:]]*—?[[:space:]]*[0-9]{1,4}[[:space:]]*—?[[:space:]]*$/d' \
    -e 's/[[:space:]]+$//' \
    "$txt" | cat -s > "$txt.clean"
  mv "$txt.clean" "$txt"
done
print "清洗完成"

print "=== 3/3 切分 (模式: $MODE) ==="
python3 - "$WORK" "$OUT_DIR" "$MODE" "$CHARS" <<'PY'
import os, re, sys, pathlib

work, out, mode, chars = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
# 条文号形态：4.2.1 / 第4.2.1条 / 4.2.1A（国标里确实有带字母的修订条）
ARTICLE = re.compile(r'^\s*(?:第\s*)?(\d+(?:\.\d+){1,3}[A-Z]?)\s*(?:条)?[\s　]')
total = 0

for txt in sorted(pathlib.Path(work).glob('*.txt')):
    body = txt.read_text(encoding='utf-8', errors='replace')
    src = txt.stem
    dest = pathlib.Path(out) / src
    dest.mkdir(parents=True, exist_ok=True)
    chunks = []

    if mode == 'by-article':
        cur_id, buf = None, []
        for line in body.splitlines():
            m = ARTICLE.match(line)
            if m:
                if cur_id and buf:
                    chunks.append((cur_id, '\n'.join(buf).strip()))
                cur_id, buf = m.group(1), [line]
            elif cur_id:
                buf.append(line)
        if cur_id and buf:
            chunks.append((cur_id, '\n'.join(buf).strip()))
        if not chunks:
            # 没匹配到条文号 —— 多半是扫描件 OCR 质量差，或非条文型文档。
            # 不静默失败，退回字数切分并告警。
            print(f'  !! {src}: 未识别到条文号，退回按 {chars} 字切分', file=sys.stderr)
            mode_local = 'fallback'
            chunks = [(f'seg{i//chars+1:04d}', body[i:i+chars])
                      for i in range(0, len(body), chars)]
    else:
        chunks = [(f'seg{i//chars+1:04d}', body[i:i+chars])
                  for i in range(0, len(body), chars)]

    for cid, text in chunks:
        if not text.strip():
            continue
        # 每个切片自带出处头 —— 这是「答案必须能点回原文」的技术前提。
        # 扣子召回时会把整个切片喂给模型，出处头跟着一起进上下文。
        fm = f'> 出处：{src} 第 {cid} 条\n\n' if mode == 'by-article' else f'> 出处：{src} 片段 {cid}\n\n'
        (dest / f'{cid}.md').write_text(fm + text.strip() + '\n', encoding='utf-8')
        total += 1
    print(f'  {src}: {len(chunks)} 片')

print(f'切分完成: 共 {total} 片 → {out}')
PY

print ""
print "语料就绪: $OUT_DIR"
print "下一步：把整个目录拖进扣子知识库（第 7 章 步骤 3）"
print "提示：条文切分模式下每片自带「出处」行，别在扣子里再开自动摘要，会把出处行吃掉。"