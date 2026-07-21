#!/usr/bin/env pwsh
# clean-corpus.ps1 —— 公开国标 PDF → 干净可入库文本（Windows 11 + PowerShell 7 版）
#
# 与 ../macos-zsh/clean-corpus.sh 逻辑等价。用途：第 2 章（第二次培训·知识库）
# 备课/核对。把兜底语料（公开国标/图集 PDF）洗成 Dify 能正确切分的 md 片段。
#
# 说明：新大纲里学员几乎纯浏览器操作、不碰命令行。此 PS7 版主要给讲师/助教在
# Windows 上核对备课产物用。
#
# 依赖：poppler（提供 pdftotext）、python3
#   scoop install poppler python    # 或 choco install poppler python
#
# 用法：
#   ./clean-corpus.ps1 -In ..\raw\pdf -Out ..\corpus\by-article -ByArticle
#   ./clean-corpus.ps1 -In ..\raw\pdf -Out ..\corpus\by-500 -ByChars 500
#
# 两种切分粒度是第 2 章「切分粒度 A/B 实验」的两个实验组。
# 同一批 PDF 跑两次，得到两个语料目录，分别灌进两个 Dify 知识库对比召回质量。

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$In,
    [Parameter(Mandatory)][string]$Out,
    [switch]$ByArticle,
    [int]$ByChars = 0
)

$ErrorActionPreference = 'Stop'

$mode  = 'by-article'
$chars = 500
if ($ByChars -gt 0) { $mode = 'by-chars'; $chars = $ByChars }

if (-not (Test-Path -PathType Container $In)) { Write-Error "输入目录不存在: $In"; exit 1 }
if (-not (Get-Command pdftotext -ErrorAction SilentlyContinue)) {
    Write-Error "缺 pdftotext。先跑: scoop install poppler（或 choco install poppler）"; exit 1
}

New-Item -ItemType Directory -Force -Path $Out | Out-Null
$work = Join-Path ([System.IO.Path]::GetTempPath()) ("clean-corpus-" + [guid]::NewGuid())
New-Item -ItemType Directory -Force -Path $work | Out-Null

try {
    Write-Host "=== 1/3 提取文本 ==="
    $count = 0
    Get-ChildItem -Path $In -Recurse -Filter *.pdf -File | ForEach-Object {
        $base = $_.BaseName
        # 规范化文件名：空格→连字符，去中英文括号，压缩多重连字符
        $slug = $base -replace '\s+', '-' `
                      -replace '[（）()《》【】]', '' `
                      -replace '-{2,}', '-' `
                      -replace '^-', '' -replace '-$', ''
        $dst = Join-Path $work "$slug.txt"
        try {
            # -layout 保留版面，表格类国标条文不会被拆成乱序
            & pdftotext -layout -enc UTF-8 $_.FullName $dst 2>$null
            $count++
            Write-Host "  ok: $slug"
        } catch {
            Write-Warning "  !! 解析失败，跳过: $base"
        }
    }
    Write-Host "提取完成: $count 份"
    if ($count -eq 0) { Write-Error "没有任何 PDF 被成功解析。检查输入目录。"; exit 1 }

    # 清洗 + 切分：交给 python（跨平台，与 zsh 版共用同一段切分逻辑）
    Write-Host "=== 2/3 清洗噪声 + 3/3 切分 (模式: $mode) ==="
    $py = @'
import os, re, sys, pathlib

work, out, mode, chars = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])

# --- 清洗：去孤立页码行 + 行尾空白 + 压缩连续空行 ---
def clean(body):
    lines, blank = [], 0
    for ln in body.splitlines():
        if re.match(r'^\s*—?\s*\d{1,4}\s*—?\s*$', ln):   # 孤立页码行
            continue
        ln = ln.rstrip()
        if not ln.strip():
            blank += 1
            if blank > 1:
                continue
        else:
            blank = 0
        lines.append(ln)
    return '\n'.join(lines)

# 条文号形态：4.2.1 / 第4.2.1条 / 4.2.1A（国标里确实有带字母的修订条）
ARTICLE = re.compile(r'^\s*(?:第\s*)?(\d+(?:\.\d+){1,3}[A-Z]?)\s*(?:条)?[\s　]')
total = 0

for txt in sorted(pathlib.Path(work).glob('*.txt')):
    body = clean(txt.read_text(encoding='utf-8', errors='replace'))
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
            chunks = [(f'seg{i//chars+1:04d}', body[i:i+chars])
                      for i in range(0, len(body), chars)]
    else:
        chunks = [(f'seg{i//chars+1:04d}', body[i:i+chars])
                  for i in range(0, len(body), chars)]

    for cid, text in chunks:
        if not text.strip():
            continue
        # 每个切片自带出处头 —— 这是「答案必须能点回原文」的技术前提。
        # Dify 召回时会把整个切片喂给模型，出处头跟着一起进上下文。
        fm = f'> 出处：{src} 第 {cid} 条\n\n' if mode == 'by-article' else f'> 出处：{src} 片段 {cid}\n\n'
        (dest / f'{cid}.md').write_text(fm + text.strip() + '\n', encoding='utf-8')
        total += 1
    print(f'  {src}: {len(chunks)} 片')

print(f'切分完成: 共 {total} 片 → {out}')
'@
    $py | & python3 - $work $Out $mode $chars
    if ($LASTEXITCODE -ne 0) { Write-Error "切分失败"; exit 1 }

    Write-Host ""
    Write-Host "语料就绪: $Out"
    Write-Host "下一步：把整个目录拖进 Dify 知识库（第 2 章 建知识库步骤）"
    Write-Host "提示：条文切分模式下每片自带「出处」行，别在 Dify 里再开自动摘要，会把出处行吃掉。"
}
finally {
    Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}
