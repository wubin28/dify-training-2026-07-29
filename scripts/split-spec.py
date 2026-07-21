#!/usr/bin/env python3
# split-spec.py —— 手写 md 规范 → Dify 可入库切片（by-article / by-chars）
# 与 clean-corpus 的区别：直接读 md，条文号正则容忍 markdown 前缀（- / > / 空白）。
# 用于 Q/SEMEDI 3—2025 内部规范语料切分（第 2 章知识库 A/B 实验）。
import re, sys, pathlib


def main():
    if len(sys.argv) < 4:
        sys.exit("用法: split-spec.py <specs.md> <输出目录> [--by-article | --by-chars N]")
    src = pathlib.Path(sys.argv[1])
    dest = pathlib.Path(sys.argv[2])
    mode = sys.argv[3]
    chars = int(sys.argv[4]) if mode == "--by-chars" and len(sys.argv) > 4 else 500
    dest.mkdir(parents=True, exist_ok=True)

    # 归一化：去掉行首 markdown 项目符号/引用符/多余空白，让条文号顶格
    raw = src.read_text(encoding="utf-8")
    lines = []
    for ln in raw.splitlines():
        s = re.sub(r'^\s*(?:[-*>]\s+)*', '', ln)   # 去 - / * / > 前缀
        lines.append(s.rstrip())
    body = "\n".join(lines)

    ART = re.compile(r'^(\d+(?:\.\d+){1,3}[A-Z]?)\s')  # 3.2.1 / 8.2.4 …

    if mode == "--by-article":
        chunks, cur, buf = [], None, []
        for ln in body.splitlines():
            m = ART.match(ln)
            if m:
                if cur and buf:
                    chunks.append((cur, "\n".join(buf).strip()))
                cur, buf = m.group(1), [ln]
            elif cur:
                buf.append(ln)          # 注: 附注跟主条同片（Q02 观测点）
        if cur and buf:
            chunks.append((cur, "\n".join(buf).strip()))
        if not chunks:
            sys.exit("未识别到条文号，检查 specs.md 格式")
    else:  # --by-chars
        flat = re.sub(r'\n{2,}', '\n', body).strip()
        chunks = [(f"seg{i//chars+1:04d}", flat[i:i+chars])
                  for i in range(0, len(flat), chars)]

    src_name = "Q/SEMEDI 3—2025《民用建筑机电与防火设计院内统一技术措施》"
    n = 0
    for cid, text in chunks:
        if not text.strip():
            continue
        # 每片自带出处头 —— 「答案能点回原文」的技术前提，召回时随片进上下文
        head = f"【出处】{src_name} 第 {cid} 条\n\n" if mode == "--by-article" \
               else f"【出处】{src_name} 片段 {cid}\n\n"
        (dest / f"{cid}.md").write_text(head + text + "\n", encoding="utf-8")
        n += 1
    print(f"切分完成（{mode}）：{n} 片 → {dest}")


if __name__ == "__main__":
    main()
