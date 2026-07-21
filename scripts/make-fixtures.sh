#!/usr/bin/env zsh
# make-fixtures.sh —— 讲师侧兜底素材生成
#
# 用途：第 12、14、15、16 章。造大纲点名要的讲师侧道具：
#   - 脱敏工程案例资料 ×2        （第三次课·项目二，给没带作业的学员）
#   - 含 5 份资料的项目包 ×1     （第四次课·项目二的循环节点）
#     └─ 其中 1 份是「故意损坏的文件」
#   - 三专业设计说明模板 ×3      （第四次课·项目二的多分支）
#   - 案例卡片字段 Schema        （第三次课·项目二的结构化输出）
#
# 依赖：无（zsh 内建 + dd）。可选 pandoc（--pdf 时把 md 转 PDF，更贴近真实课堂输入）
#
# 用法：
#   ./make-fixtures.sh --out ../fixtures
#   ./make-fixtures.sh --out ../fixtures --pdf            # 需 brew install pandoc basictex
#   ./make-fixtures.sh --out ../fixtures --corrupt garbage # 扣子太宽容时换这个
#
# 关于「损坏文件」的设计（第 15 章验收线的关键道具）：
#   随机字节做的假 PDF 会被扣子在上传阶段直接拒收 —— 那测不到工作流的异常分支，
#   流程根本没跑起来。要的是「能上传、解析时炸」。
#
#   两种模式：
#   truncate（默认）：真 PDF 截掉尾部 65%。文件头合法（能过上传的类型校验），
#       xref/trailer/%%EOF 全丢（规范意义上已损坏）。
#       ⚠️ 已实测：macOS Quick Look 仍能预览它 —— 宽容解析器会扫描重建 xref。
#       所以扣子**有可能**也能解析出部分文本。第 15 章首次实操时务必实测，
#       若扣子照单全收，换 garbage 模式。
#   garbage：合法 PDF 头 + 随机字节 + 无任何合法对象。任何解析器都救不回来，
#       但仍能过「是不是 PDF」的类型校验。代价是不如 truncate 真实
#       （truncate 更像现实里的「传输中断的扫描件」）。

set -euo pipefail

OUT=""
MAKE_PDF=0
CORRUPT_MODE="truncate"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out)     OUT="$2"; shift 2 ;;
    --pdf)     MAKE_PDF=1; shift ;;
    --corrupt) CORRUPT_MODE="$2"; shift 2 ;;
    -h|--help) sed -n '2,34p' "$0"; exit 0 ;;
    *) print -u2 "未知参数: $1"; exit 1 ;;
  esac
done
[[ "$CORRUPT_MODE" != "truncate" && "$CORRUPT_MODE" != "garbage" ]] && {
  print -u2 "--corrupt 只能是 truncate 或 garbage"; exit 1; }
[[ -z "$OUT" ]] && { print -u2 "用法: $0 --out <输出目录> [--pdf]"; exit 1; }

mkdir -p "$OUT"/{cases,project-pack,templates,schema}

print "=== 1/4 脱敏工程案例资料 ×2 ==="

cat > "$OUT/cases/case-01-某科技园研发楼.md" <<'EOF'
# 某科技园研发楼项目资料（脱敏样本 01）

## 项目概况
项目名称：XX 科技园二期研发楼
建设地点：华东地区某市高新区（脱敏）
建设单位：某科技发展有限公司（脱敏）
用地面积：18,600 m²
总建筑面积：42,800 m²（地上 34,200 m²，地下 8,600 m²）
建筑高度：47.9 m，地上 11 层，地下 1 层
结构形式：钢筋混凝土框架-剪力墙结构
设计阶段：施工图（已完成）
竣工时间：2024 年 11 月

## 技术难点
1. 用地紧张，地下室外墙紧邻既有地铁隧道保护区，基坑支护采用地下连续墙加三道内支撑。
2. 研发楼中部设 3 层通高中庭，防火分区面积超标，采用防火卷帘加自动喷水灭火系统局部应用，
   经消防性能化评估通过。
3. 实验区排风系统与办公区新风系统需完全独立，机电管线在层高 4.2 m 内排布困难。

## 创新做法
- 中庭采用可开启天窗联动排烟，兼顾平时自然通风，年空调能耗较基准降低约 12%。
- 结构采用 BIM 正向设计，钢筋碰撞检查前置，现场返工率显著下降。

## 可复用经验
- 邻近地铁的基坑，建议在方案阶段即介入地铁保护评估，避免施工图阶段推翻支护方案。
- 通高中庭的防火分区问题，性能化评估周期约 6–8 周，须在进度计划中预留。

## 附图
（本脱敏样本不含图纸）
EOF

cat > "$OUT/cases/case-02-某医院门诊综合楼.md" <<'EOF'
# 某医院门诊综合楼项目资料（脱敏样本 02）

## 项目概况
项目名称：XX 市第二人民医院门诊综合楼
建设地点：华中地区某市（脱敏）
建设单位：某市卫生健康委员会（脱敏）
总建筑面积：58,300 m²
建筑高度：23.8 m，地上 5 层，地下 2 层
结构形式：钢筋混凝土框架结构
设计阶段：施工图
竣工时间：2025 年 6 月

## 技术难点
1. 院区不停诊改造，需分三期施工，每期均须保证门诊流线与急救通道连续。
2. 洁污分流要求高，医疗街与污物通道完全分离，平面组织受既有院区管网制约。
3. 手术室区域对振动敏感，紧邻城市主干道，采用隔振基础与浮筑楼板。

## 创新做法
- 采用「医疗街 + 模块化科室单元」布局，后期科室调整不动主体结构。
- 屋面设置直升机停机坪，与急诊电梯直连。

## 可复用经验
- 不停诊改造项目，分期界面的临时封堵与消防疏散补充方案，必须在初步设计阶段就与
  消防审查部门沟通，否则施工图阶段极易返工。
- 医院项目的机电管线综合，建议预留 15% 的竖向空间冗余给后期科室改造。

## 附图
（本脱敏样本不含图纸）
EOF

print "  ok: 2 份脱敏案例（cases/）"

print "=== 2/4 含 5 份资料的项目包（含 1 份损坏件）==="

PACK="$OUT/project-pack"

cat > "$PACK/01-项目任务书.md" <<'EOF'
# 某文化中心项目设计任务书（脱敏）

建设单位：某区文化和旅游局（脱敏）
项目性质：新建
用地面积：24,500 m²
拟建总建筑面积：31,000 m²
功能构成：图书馆 12,000 m²、剧场 9,000 m²（800 座）、展厅 6,000 m²、配套 4,000 m²
限高：36 m
设计阶段：方案 → 初步设计
主导专业：建筑
EOF

cat > "$PACK/02-建筑设计条件.md" <<'EOF'
# 建筑专业设计条件

- 抗震设防烈度：7 度（0.10g），设计地震分组第二组
- 场地类别：II 类
- 建筑分类：多层公共建筑，耐火等级一级
- 剧场部分按人员密集场所设计，疏散按 GB 50016 及 JGJ 57 执行
- 图书馆书库荷载按 12 kN/m² 取值
- 绿建目标：二星级
EOF

cat > "$PACK/03-结构设计条件.md" <<'EOF'
# 结构专业设计条件

- 结构体系：剧场部分大跨钢结构（最大跨度 36 m），图书馆及展厅部分框架-剪力墙
- 基础形式：桩基础，预应力管桩
- 地下水位：埋深约 2.1 m，需考虑抗浮
- 混凝土强度等级：C30–C40
- 钢材：Q355B
EOF

cat > "$PACK/04-机电设计条件.md" <<'EOF'
# 机电专业设计条件

- 空调冷热源：地源热泵 + 冷水机组调峰
- 剧场观众厅采用座椅送风，噪声控制 NR-25
- 供电负荷等级：剧场舞台照明及消防负荷为一级，其余二级
- 消防：全楼设自动喷水灭火系统，剧场舞台设雨淋系统
- 智能化：设 BA 系统，预留智慧图书馆接口
EOF

# ---- 损坏件 ----
# 先用一份合法 PDF 打底。优先借用系统自带 PDF；没有就用 zsh 手搓一个最小合法 PDF。
SEED_PDF="$PACK/.seed.pdf"
FOUND=""
for cand in \
  /System/Library/Automator/*.action/Contents/Resources/*.pdf(N) \
  /Library/Desktop\ Pictures/*.pdf(N) \
  /System/Library/Frameworks/**/*.pdf(N[1]) ; do
  [[ -f "$cand" ]] && { FOUND="$cand"; break }
done

if [[ -n "$FOUND" ]] && [[ $(stat -f%z "$FOUND") -gt 20000 ]]; then
  cp "$FOUND" "$SEED_PDF"
  print "  种子 PDF：借用系统文件 ${FOUND:t}"
else
  # 手搓最小合法 PDF（含 xref，能被正常打开）
  python3 - "$SEED_PDF" <<'PY'
import sys, zlib
path = sys.argv[1]
text = b'BT /F1 12 Tf 72 720 Td (Design Note - fixture seed) Tj ET\n' * 400
objs = [
    b'<< /Type /Catalog /Pages 2 0 R >>',
    b'<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    b'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R '
    b'/Resources << /Font << /F1 5 0 R >> >> >>',
    b'<< /Length %d >>\nstream\n' % len(text) + text + b'\nendstream',
    b'<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
]
out, offsets = b'%PDF-1.4\n', []
for i, o in enumerate(objs, 1):
    offsets.append(len(out))
    out += b'%d 0 obj\n' % i + o + b'\nendobj\n'
xref = len(out)
out += b'xref\n0 %d\n0000000000 65535 f \n' % (len(objs) + 1)
for off in offsets:
    out += b'%010d 00000 n \n' % off
out += b'trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n' % (len(objs) + 1, xref)
open(path, 'wb').write(out)
PY
  print "  种子 PDF：手搓生成"
fi

SEED_SIZE=$(stat -f%z "$SEED_PDF")
BROKEN="$PACK/05-历史图纸扫描件.pdf"

if [[ "$CORRUPT_MODE" == "truncate" ]]; then
  KEEP=$(( SEED_SIZE * 35 / 100 ))   # 留头部 35%，砍掉含 xref/trailer/%%EOF 的尾部
  dd if="$SEED_PDF" of="$BROKEN" bs=1 count=$KEEP 2>/dev/null
  print "  ok: 5 份资料（project-pack/），其中 05-历史图纸扫描件.pdf 为损坏件"
  print "      模式 truncate：原始 ${SEED_SIZE}B → ${KEEP}B"
else
  python3 - "$BROKEN" <<'PY'
import os, sys
# 合法头（过类型校验）+ 随机字节（无任何可解析对象）+ 无 xref/trailer/EOF
open(sys.argv[1], 'wb').write(b'%PDF-1.4\n%\xe2\xe3\xcf\xd3\n' + os.urandom(24000))
PY
  print "  ok: 5 份资料（project-pack/），其中 05-历史图纸扫描件.pdf 为损坏件"
  print "      模式 garbage：合法头 + 24KB 随机字节"
fi
rm -f "$SEED_PDF"

# 结构校验（不用 qlmanage —— 它是 GUI 工具，会挂住，且会重建 xref 给你假信号）
python3 - "$BROKEN" <<'PY'
import sys
d = open(sys.argv[1], 'rb').read()
ok = d[:5] == b'%PDF-'
bad = not any(m in d for m in (b'xref', b'trailer', b'%%EOF'))
print(f'      校验：PDF头={"合法" if ok else "非法"}  xref/trailer/EOF={"已丢" if bad else "仍在（不够坏！）"}')
if not (ok and bad):
    print('      !! 损坏件不合格 —— 上传或异常分支会测不出来', file=sys.stderr)
PY
print "      ⚠️ 最终验证只能在扣子上做（第 15 章）：能上传、解析失败 = 合格。"
print "         若扣子照单全收解析出了文本，重跑：--corrupt garbage"

print "=== 3/4 三专业设计说明模板 ==="

for spec in 建筑 结构 机电; do
  cat > "$OUT/templates/设计说明模板-${spec}.md" <<EOF
# ${spec}专业设计说明模板（通用兜底版）

> 用途：第四次课·项目二「多分支」节点的模板载荷。
> 学员没带本专业模板时用这份。字段刻意留空 —— 空字段是给
> 「缺失字段不许猜」这条底线做验证的。

## 一、工程概况
项目名称：{{项目名称}}
建设地点：{{建设地点}}
建设规模：{{总建筑面积}}
设计阶段：{{设计阶段}}

## 二、设计依据
1. 建设单位提供的设计任务书
2. {{适用规范清单}}
3. {{上阶段审查意见}}

## 三、${spec}专业设计说明
### 3.1 设计范围
{{设计范围}}

### 3.2 主要技术指标
{{技术指标表}}

### 3.3 ${spec}专业主要设计内容
{{专业设计内容}}

### 3.4 需说明的特殊问题
{{特殊问题}}

## 四、规范符合性自检
| 检查项 | 依据条文 | 结论 |
|---|---|---|
| {{检查项}} | {{条文号}} | {{符合/不符合/待确认}} |
EOF
done
print "  ok: 3 份模板（templates/）"

print "=== 4/4 案例卡片 Schema ==="

cat > "$OUT/schema/case-card.schema.json" <<'EOF'
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "工程案例卡片",
  "description": "第三次课·项目二的结构化输出契约。字段与飞书多维表格列一一对应。",
  "type": "object",
  "properties": {
    "project_name":   { "type": "string", "description": "项目名称。资料里没有则留空字符串，不许推测。" },
    "location":       { "type": "string", "description": "建设地点，精确到市/区" },
    "scale":          { "type": "string", "description": "建设规模，含总建筑面积与层数" },
    "discipline":     { "type": "string", "enum": ["建筑", "结构", "机电", "其他", ""] },
    "difficulties":   { "type": "array", "items": { "type": "string" }, "description": "技术难点，逐条" },
    "innovations":    { "type": "array", "items": { "type": "string" }, "description": "创新做法，逐条" },
    "reusable":       { "type": "array", "items": { "type": "string" }, "description": "可复用经验，逐条" },
    "images":         { "type": "array", "items": { "type": "string" }, "description": "图片链接" },
    "missing_fields": {
      "type": "array", "items": { "type": "string" },
      "description": "资料中未提供、因而留空的字段名。这是底线机制：宁可在这里列一长串，也不许猜一个值填进去。"
    }
  },
  "required": ["project_name", "location", "scale", "discipline", "missing_fields"]
}
EOF

cat > "$OUT/schema/case-card.prompt.md" <<'EOF'
# 案例收集智能体 —— 结构化输出提示词片段

严格按下列 JSON Schema 输出，不要输出任何 JSON 以外的内容（不要前言、不要 markdown 代码块围栏）。

铁律：
1. 资料中没有明确写出的信息，对应字段留空字符串或空数组，并把字段名加入 missing_fields。
2. 禁止根据常识、行业惯例或项目名称推测任何字段值。宁可留空。
3. difficulties / innovations / reusable 三个字段必须是对原文的提炼，不是发挥。
   每一条都应能在原文中找到出处句。
4. discipline 只能取 建筑 / 结构 / 机电 / 其他 之一；判断不了就填「其他」，不要猜。

Schema：
（把 case-card.schema.json 的内容粘在这里）
EOF

print "  ok: Schema + 提示词片段（schema/）"

if [[ $MAKE_PDF -eq 1 ]]; then
  if command -v pandoc >/dev/null; then
    print "=== 附加：md → PDF ==="
    for md in "$OUT"/cases/*.md "$PACK"/0[1-4]*.md; do
      pandoc "$md" -o "${md:r}.pdf" --pdf-engine=xelatex \
        -V CJKmainfont="PingFang SC" 2>/dev/null && print "  ok: ${md:t:r}.pdf" \
        || print -u2 "  !! 转换失败（缺 xelatex？跑 brew install basictex）: ${md:t}"
    done
  else
    print -u2 "!! 没装 pandoc，跳过 PDF 转换。brew install pandoc basictex"
  fi
fi

print ""
print "兜底素材就绪: $OUT"
print ""
print "清单："
print "  cases/         → 第 12 章（案例收集智能体的输入，给没带作业的学员）"
print "  project-pack/  → 第 15 章（循环节点的 5 份资料，含 1 份损坏件）"
print "  templates/     → 第 15 章（多分支的三专业模板）"
print "  schema/        → 第 11 章（案例卡片结构化输出契约）"
