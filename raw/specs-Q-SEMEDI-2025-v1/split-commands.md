# Q/SEMEDI 3—2025 语料切分命令（喂第 2 章知识库 A/B 实验）

> 关联：`specs.md`（内部规范全文）、v3 指南 0.4 双平台速查、第 2 章切分粒度 A/B。

## 为什么不用现成的 clean-corpus

`clean-corpus.sh/.ps1` 是为**公开国标 PDF** 设计的：只吃 `raw/pdf/*.pdf`，走 `pdftotext`，by-article 正则 `^\s*(\d+(?:\.\d+){1,3})` **顶格**匹配条文号。

我们的 `specs.md` 是**手写 markdown**，两处不合：
1. **没有 PDF 源**——转 PDF 要 pandoc + xelatex + 中文字体，坑深且没必要；
2. 条文行前有 markdown 项目符号 `- 3.2.1 …`，顶格正则失配 → 会退回字数切分，**by-article 组作废**。

所以直接读 md 切，正则已适配 `- `/`> ` 前缀。产出目录结构与 clean-corpus 一致（`corpus/by-article/<规范名>/<条文号>.md`），第 2 章上传 Dify 的流程不变。

---

## 一次性切分命令（zsh + pwsh）

**约定路径**（按 v3 指南，`corpus/` 落在 katas 项目根下）：
- 输入：`SPEC`（vault 里的 specs.md）
- 输出：`corpus/by-article/Q-SEMEDI-3-2025/*.md` 与 `corpus/by-500/Q-SEMEDI-3-2025/*.md`

### zsh（讲师 Mac，iTerm2）

```zsh
cd /Users/binwu/OOR/katas/dify-training-2026-07-29

SPEC="/Users/binwu/OOR/remote-vault-on-mbp/my-workspace/my-training-outlines/2026-07-15-shanghai-institute-dify-training-by-diana/raw/specs-Q-SEMEDI-2025/specs.md"

# 按条文切（实验组 A）
python3 scripts/split-spec.py "$SPEC" ./corpus/by-article/Q-SEMEDI-3-2025 --by-article
# 按 500 字切（实验组 B）
python3 scripts/split-spec.py "$SPEC" ./corpus/by-500/Q-SEMEDI-3-2025 --by-chars 500
```

### PowerShell 7（Windows 上模仿学员/助教）

```powershell
cd C:\path\to\katas\dify-training-2026-07-29

$Spec = "\\vault\...\raw\specs-Q-SEMEDI-2025\specs.md"   # 换成 Windows 上的实际路径

python3 scripts\split-spec.py $Spec .\corpus\by-article\Q-SEMEDI-3-2025 --by-article
python3 scripts\split-spec.py $Spec .\corpus\by-500\Q-SEMEDI-3-2025 --by-chars 500
```

> 两平台跑同一个 `scripts/split-spec.py`（下方给出全文），产出一致。只依赖 python3 标准库，不需要 poppler/pandoc。

---

## scripts/split-spec.py（放到 katas 的 scripts/ 下）

```python
#!/usr/bin/env python3
# split-spec.py —— 手写 md 规范 → Dify 可入库切片（by-article / by-chars）
# 与 clean-corpus 的区别：直接读 md，条文号正则容忍 markdown 前缀（- / > / 空白）。
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
```

---

## 切完后（第 2 章上传 Dify）

1. `corpus/by-article/Q-SEMEDI-3-2025/` 灌进知识库 A（按条文切）；
2. `corpus/by-500/Q-SEMEDI-3-2025/` 灌进知识库 B（按 500 字切）；
3. 两库都配 向量 + 关键词(BM25) + Rerank，用 `run-eval` 跑 `questions.yaml` 对比；
4. 重点看 **Q02**：0.5 倍那条附注在 by-article 里跟主条同片、答得全；by-500 易被 500 字边界切断、召回不全——切分粒度价值当场可见。

## 零脚本备选（临场省事）

不想跑脚本，可把 `specs.md` 直接拖进 Dify 知识库，用 Dify 界面切分设置做 A/B：
- A 组：自定义分段，分段标识符设为条文号模式 / 段落；
- B 组：固定长度 500 字。
效果近似，但**离线切分的切片自带出处头、召回溯源更干净**，正式备课仍建议用上面的脚本。
