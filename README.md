# 第三次培训 · Windows 11 现场实操指南（全自包含）

> 生成日期：2026-07-23
> 用途：**讲师上课前一天在客户现场讲师专用演示的 Windows 11 电脑上，把课程完整实操走一遍**；也供学员在 Windows 11 上跟做。把原先分散在 `08-2 / 18-1 / 20-1 / 22-1` 多个 wiki 文件里的内容，按上课顺序合并为一份自包含手册。
> 适用环境：Windows 11 + **PowerShell 7** + 浏览器接**院内 DIFY v1.11.2**。
> **前提**：使用设计院内部电脑的讲师和学员，**已能访问院内的 Dify 基础设施**（院内已预置 embedding、chat 模型）——所以本文**不含**本地起 Dify、不含 ollama/bge-m3/代理修复（那是讲师在 Mac 备 Dify 基础设施才需要，见 `23-2-hands-on-guide-for-mac-for-3rd-training.md`）。命令行仅用于**洗语料**与**批量召回对比**，其余全走浏览器操作院内 Dify。
> 项目根：`/Users/binwu/OOR/katas/dify-training-2026-07-29`（等价 Windows 路径，脚本已在库、GitHub 远程已配好：`git@github.com:wubin28/dify-training-2026-07-29.git`）。

---

## 目录

- [0. 开工前必读](#0-开工前必读)
- [1. 洗语料（PowerShell 7）](#1-洗语料)
- [2. 知识库 A/B 召回命中对比（核心产出）](#2-知识库-ab-召回命中对比)
- [3. 搭好规范问答助手后如何验证正常工作](#3-搭好后如何验证)
- [4. 日常 AI 办公怎么用规范问答助手](#4-日常-ai-办公怎么用)
- [5. 案例收集助手实操（聊天助手/对话访谈式填卡）](#5-案例收集助手实操)

---

## 0. 开工前必读

### 0.1 这份指南是什么

- **是**：讲师在客户 Windows 11 演示机上上课前一天把实操过一遍、上课时现场带做的操作手册。跑通了，现场才不慌。
- 命令行只出现在**洗语料**（第 1 章）与**批量召回对比**（第 2 章 4b，可选）；其余步骤（建知识库、召回测试、搭助手、验证、发布）**一律浏览器操作院内 DIFY v1.11.2**。

### 0.2 角色与设备（院内基础设施已就绪）

| 角色 | 设备 | 干什么 |
|---|---|---|
| **讲师现场演示 / 学员跟做** | Windows 11 + PowerShell 7 + 浏览器 | **几乎纯浏览器操作院内 DIFY（v1.11.2）**；embedding、chat 模型院内已预置，不用自己配 |
| **命令行（仅洗语料/跑对比）** | Windows 11 + PowerShell 7 | 跑 `scripts/windows-pwsh/` 下的 pwsh 脚本 |

> 本文只保留 **PowerShell 7（Windows）** 命令。zsh（讲师 Mac）段一律省略——那是讲师在 Mac 备 Dify 基础设施才用，见 `23-2`。

### 0.3 scripts 目录结构

```
katas\dify-training-2026-07-29\      # 项目根
├── scripts\
│   ├── questions.yaml            # 平台无关验收题库（留在根，runner 共用）
│   ├── split-spec.py            # markdown 规范切分器
│   └── windows-pwsh\            # Windows 11 + PowerShell 7
│       ├── clean-corpus.ps1
│       ├── make-fixtures.ps1
│       ├── run-eval.ps1
│       ├── dify-up.ps1           # 本地起 Dify（现场用院内 Dify，通常不需要）
│       └── dify-down.ps1
├── raw\pdf        # 公开国标 PDF 原件
├── corpus\        # 切分输出（by-article / by-500）
├── fixtures\      # make-fixtures 输出
├── eval\          # run-eval / 召回对比输出
└── catchup-packs\ # 追赶包导出件
```

> **★ 路径最易踩的坑**：`cd` 进 `scripts\windows-pwsh\` 后，当前目录到项目根是 `..\..`。所以命令行输出目标写 `..\..\corpus`、`..\..\fixtures`、`..\..\eval`、`..\..\raw\pdf`。脚本内部对 `questions.yaml` 的引用已是 `..\questions.yaml`（脚本自己处理）。

### 0.4 一次性环境准备（PowerShell 7）

> 顺序：先判 python；python 没装再看 scoop；scoop 没装，按下面「用代理／不用代理」二选一装好，再装工具。**已装的直接跳到第 3 步。**

**第 0 步 · 判断本机是否已装 python**

```powershell
Get-Command python -ErrorAction SilentlyContinue    # 有输出 = 命令存在
python --version                                     # 显示 Python 3.x.x = 真已装
```

- 出现版本号（如 `Python 3.12.4`）→ python 已就绪，**跳到第 3 步**。
- 报错／无输出／**弹出「Microsoft Store」页面** → 没真装（那是 Windows 的 Store 别名桩，不是真 python），继续第 1 步。
- 注：Windows 上命令是 `python`，不是 `python3`（`python3` 常无法识别）。

**第 0.1 步 · 安装vscode以便查看和编辑源代码**

用浏览器访问[https://code.visualstudio.com/download](https://code.visualstudio.com/download)下载并安装vscode，安装完成后可以用vscode打开和编辑源代码文件。

**第 1 步 · 判断是否已装 scoop（仅当 python 没装时才做）**

```powershell
Get-Command scoop -ErrorAction SilentlyContinue     # 有输出 = 命令存在
scoop --version                                      # 显示版本号 = 真已装
```

- 出现版本号 → scoop 已就绪，**跳到第 3 步**用 scoop 装 python。
- 报错／无输出 → 没装 scoop，继续第 2 步。

**第 2 步 · 装 scoop（中国大陆学员：用代理／不用代理，二选一）**

先放开当前用户的执行策略（两方案都需要，只跑一次）：

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
```

**方案 A · 有代理**（推荐；装好后 scoop 下载/更新也走代理更稳）：

```powershell
$env:HTTP_PROXY  = 'http://127.0.0.1:7890'   # ← 按你代理软件端口改；Clash/mihomo 默认 7890
$env:HTTPS_PROXY = 'http://127.0.0.1:7890'
Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
scoop config proxy 127.0.0.1:7890            # 让 scoop 后续更新/装包也走代理
```

**方案 B · 无代理**（走 gitee 镜像，纯国内网络可达）：

```powershell
Invoke-RestMethod -Uri https://gitee.com/glsnames/scoop-installer/raw/master/bin/install.ps1 | Invoke-Expression
scoop config SCOOP_REPO 'https://gitee.com/glsnames/scoop-installer'   # scoop 自身更新也走镜像
```

- 验证：`scoop --version` 有版本号 = 装好。

**第 2.1 步 · 如何判断python是否由 scoop安装**

你可以用以下方法在 PowerShell 7 里快速判断：

查看 Python 安装路径（最直观）

```powershell
(Get-Command python).Source
```

或者：

```powershell
where.exe python
```

**判断依据：**

- **Scoop 安装** → 路径会包含 `\scoop\`，例如： `C:\Users\你的用户名\scoop\apps\python\current\python.exe`
- **Chocolatey 安装** → 路径会包含 `\Chocolatey\`，例如： `C:\ProgramData\chocolatey\lib\python3\tools\python.exe`
- **winget 安装** → 通常在 `C:\Program Files\` 或 `C:\Users\用户名\AppData\Local\Microsoft\WinGet\`
- **官方安装程序** → 通常在 `C:\Program Files\Python311\` 或 `C:\Users\用户名\AppData\Local\Programs\Python\`


**第 3 步 · 装语料/素材工具（原有内容，保留）**

```powershell
# 语料/素材工具（scoop 或 choco 任一）
# 若python已经安装，则去掉下面命令中的`python`，只装 poppler 和 pandoc
scoop install poppler python pandoc     # 或：choco install poppler python pandoc
python --version                         # run-eval.ps1 / make-fixtures.ps1 依赖（标准库即可，不用 pip）
# 注：pandoc 仅 make-fixtures.ps1 -Pdf 时需要；poppler 提供 clean-corpus 用的 pdftotext
```

> 参数命名习惯：pwsh 用 `-PascalCase`；开关型 `-ByArticle`，带值型 `-ByChars 500`（对应 zsh 的 `--by-article`、`--by-chars 500`）。

### 0.5 占位符约定

拿不到院内实情处用 `【待回填:xxx】`，拿到院内信息后替换。高频：
- `【待回填:DIFY_API_BASE】`——院内 DIFY API 基地址（拿到院内账号后填，第 2 章 4b 用）；
- `【待回填:embedding模型】`——院内 embedding 供应商/模型名；
- `【待回填:app-key】`——各应用 API Key（在 Dify 应用「访问 API」里复制）；
- `【待回填:条文号】`、`【待回填:评分标准】`、`【待回填:案例字段】`。

---

## 1. 洗语料

> 目的：产出 `corpus\by-article`（按条文切，实验组 A）与 `corpus\by-500`（按 500 字切，实验组 B）两套语料，作第 2 章切分粒度 A/B 实验的两组输入。
> **需要在备课的 Windows 11 PowerShell 7 里运行脚本来洗语料。**

**PowerShell 7（切分pdf格式的原生文字版GB50016-2014，仅供体验切分pdf格式文件，之后并不用它实操）**：

```powershell
# 在终端进入本代码库`dify-training-2026-07-29`的根目录，然后运行下面的命令
cd scripts\windows-pwsh
./clean-corpus.ps1 -In ..\..\raw\pdf -Out ..\..\corpus\by-article -ByArticle
./clean-corpus.ps1 -In ..\..\raw\pdf -Out ..\..\corpus\by-500 -ByChars 500
```

- *期望结果*：`corpus\by-article` 与 `corpus\by-500` 两套切分产出。
- *一致性*：pwsh 版跑的是同一段清洗/切分 python（pwsh 版内嵌 here-string），产出应与 Mac 版一致；靠 `scoop install poppler` 提供的 `pdftotext`。
- *避坑*：在 `windows-pwsh\` 子目录里跑，输出目标是 `..\..\corpus` 不是 `..\corpus`，否则落错地方。

**PowerShell 7（切分markdown格式的演示用内部规范Q-SEMEDI-3-2025-v1，之后用它实操）**：

若语料是 markdown（非 PDF），用切分器（等价 Mac 版 `split-spec.py`）：
```powershell
# 在终端进入本代码库`dify-training-2026-07-29`的根目录，然后运行下面的命令
$SPEC = "raw\specs-Q-SEMEDI-2025-v1\specs.md"
python3 scripts\split-spec.py "$SPEC" .\corpus\by-article\Q-SEMEDI-3-2025-v1 --by-article
python3 scripts\split-spec.py "$SPEC" .\corpus\by-500\Q-SEMEDI-3-2025-v1 --by-chars 500
```
---

## 2. 知识库 A/B 召回命中对比

> 目标：把「按条文切（A）vs 按 500 字切（B）」的差异，落成 2~3 题浏览器抽验截图（+ 可选批量矩阵）。
> 前提：**院内 DIFY v1.11.2** 已可登录、embedding（院内预置）与 chat 模型已就绪；第 1 章两套语料已在磁盘。
> **现场以浏览器召回测试为主**（跨平台、零命令行）；批量矩阵为可选增强。

### 2.1 本次语料实况（先看清，再动手）

| | 知识库 A（`by-article`，按条文切） | 知识库 B（`by-500`，按 500 字切） |
|---|---|---|
| 文件数 | **18 个** `*.md`（每条一文件：`3.2.1.md`…） | **4 个** `seg0001.md`…`seg0004.md` |
| 每段体量 | 每条 ~140 字，一条一段、完整 | 每片 ~500 字，跨多条、把条文/附注切断 |
| 出处头 | 每段自带 `【出处】…第 X.X.X 条` | 每片只标 `【出处】…片段 segNNNN`（丢了条文号） |
| 段数（入库后） | ≈ **18 段** | ≈ **4 段** |

> 关键教学点（比「段多段少」更本质）：**A** 每段 = 一条完整条文含附注（例 `3.2.1` 的 `2000㎡` 主条与「增加 0.5 倍」附注同段），出处精确到条文号；**B** 500 字硬切，主条与附注可能落进不同片段、相邻条文被拼一起、出处只剩 `segNNNN` 溯不回条文号。A/B 差距体现在两处：**① 命中内容是否完整（附注在不在）② 出处能否溯回条文号**。
> 注意：v3 指南通用说法「B 段更多」在**本语料下相反**（条文短），按上表真实数字验收。

核对命令（PowerShell 7，操作前先跑）：

```powershell
# 在终端进入本代码库`dify-training-2026-07-29`的根目录，然后运行下面的命令
(Get-ChildItem corpus\by-article\Q-SEMEDI-3-2025\*.md).Count   # A：应为 18
(Get-ChildItem corpus\by-500\Q-SEMEDI-3-2025\*.md).Count        # B：应为 4
Get-Content corpus\by-article\Q-SEMEDI-3-2025\3.2.1.md          # 应含 2000㎡ 主条 + 0.5 倍附注
```
- **通过判据**：A=18、B=4；`3.2.1.md` 里同时出现 `2000㎡` 和「增加 0.5 倍」。数字不符 → 语料被改动，回第 1 章重切。

### 2.2 步骤 1 · 确认 embedding 就位（院内已预置）

- 浏览器：院内 Dify 设置 → 模型供应商 → embedding 类目，有一个 **Text Embedding** 模型（院内 `【待回填:embedding模型】`），状态**已启用/正常**。
- 院内已预置 embedding，学员不受影响。若你在自己电脑本地起 Dify 备课，才需自己配（见 `23-2` 第 2 章）。

### 2.3 步骤 2 · 建知识库 A（按条文切）★对比主角之一

**操作前检验**（PowerShell 7）：

```powershell
Get-ChildItem corpus\by-article\Q-SEMEDI-3-2025\*.md | Select-Object -ExpandProperty FullName
Write-Host "路径：$(Get-Location)\corpus\by-article\Q-SEMEDI-3-2025\"
```

**浏览器操作**：
1. 知识库 → 创建知识库。
2. **导入已有文本** → 一次选中该目录下**全部 18 个 md** → 下一步。
3. **分段设置**选 **自定义**：分段标识符设一个几乎不出现的串（如 `\n-----\n`）；**分段最大长度调到 1000**（每条才 ~140 字，1000 足够「一文件＝一段」，Dify 不会二次切碎）。
4. **索引方式**：高质量；**Embedding 模型**选院内 embedding。
5. **检索设置**：向量检索；**先不开 Rerank**（A/B 要用同一档设置才可比）。
6. 保存处理，等所有文档变「可用」。

**操作后检验**：段落数 ≈ 18；点开 `3.2.1` 那段：`2000㎡` 与「增加 0.5 倍」附注同段、头部保留 `【出处】…第 3.2.1 条`。**记 A 的 dataset_id**（地址栏 `.../datasets/<A-DATASET-ID>/documents` 中间 UUID，4b 要用）。
- 不通过：段数远大于 18（被切碎）→ 最大长度设小或分隔符命中条文内换行，调大最大长度/换分隔符，**删档重传**（v1.11.2 无批量再索引）。

### 2.4 步骤 3 · 建知识库 B（按 500 字切）★对比主角之二

**操作前检验**（PowerShell 7）：

```powershell
# 在终端进入本代码库`dify-training-2026-07-29`的根目录，然后运行下面的命令
Get-ChildItem corpus\by-500\Q-SEMEDI-3-2025\*.md | Select-Object -ExpandProperty FullName
Get-Content corpus\by-500\Q-SEMEDI-3-2025\seg0001.md -Tail 3   # 看 B 把一条切断的样子
```

**浏览器操作**（与 A 除文件与分段长度外全相同，保证唯一变量是切分粒度）：导入该目录 4 个 md；分段自定义、**最大长度 500**；索引高质量、Embedding 同选院内 embedding；检索设置**与 A 完全一致**（向量检索、不开 Rerank）。等「可用」。

**操作后检验**：段落数 ≈ 4；点开任一段能看到多条被拼一起、某条被中间截断、头部只剩 `【出处】…片段 seg000X`（无条文号）。**记 B 的 dataset_id**。

### 2.5 步骤 4 · 召回命中对比（本章核心产出）★

#### 4a · 浏览器召回测试（抽 3 题，出截图）★现场主推

进**知识库 A** → 召回测试 → 输入每个 query → 记命中段、score；再进**知识库 B** 用同一 query 测一遍。

| 抽验题 | query | 看什么 |
|---|---|---|
| **Q02** | 本院设计文件编号规则由哪四段组成？ | **附注跨切分点**——A 命中 `8.1.1` 单段含「专业代号—项目号—册号—版本号」；B 该条被切成 `seg0003`(结尾 `…册`)/`seg0004`(开头 `号—版本号…`)两片，溯不回条文号 |
| **Q05** | 建筑高度大于 100m 的民用建筑，其楼板耐火极限不应低于多少？ | **精准值**——A 命中 `4.1.3`(2.50h)干净；B 片段里 `4.1.3` 可能与相邻 `4.1.5`(3.50h)混在一段，易串值 |
| **Q08** | 汽车库的防火分类分几类？ | **陷阱题**——语料里根本没有；A、B 都应无相关高分命中（证明知识库确实没有，问答应用该拒答） |

- 判据：**Q02** A 顶命中出处=`第 8.1.1 条`且四段编号完整，B 顶命中=`片段 segNNNN` 且规则被截断 → 截图存证 A、B 各一张；**Q05** A 命中 `4.1.3`=`2.50h` 不掺别值，B `2.50h` 与 `3.50h` 同框易误读 → 截图；**Q08** A、B 顶命中 score 都偏低/无关 → 截图（作「陷阱题必须拒答」的召回侧证据）。
- 这三组对比截图 = 课堂展示「按条文切 vs 按 500 字切」的核心素材。

#### 4b · 批量对比（全 10 题，出矩阵）——可选增强

用 Dify v1.11.2 的**知识库 hit-testing API**（`POST {base}/datasets/{dataset_id}/hit-testing`）对 A、B 各跑一遍 `questions.yaml`。**用「知识库 API 密钥」(`dataset-…`)，不是应用密钥 (`app-…`)。**

**拿齐三样输入**：① 知识库 API 密钥（任一知识库页 → 左下角 **服务API 访问** → API 密钥 → 创建密钥，复制 `dataset-xxxx`）；② A、B 的 dataset_id；③ 院内 API base `【待回填:DIFY_API_BASE】`（形如 `http://<院内地址>/v1`）。

**冒烟（PowerShell 7，用 `Invoke-RestMethod`，别用 `curl` 别名）**：

```powershell
$base = '【待回填:DIFY_API_BASE】'      # 如 http://<院内地址>/v1
$kbKey = 'dataset-xxxxxxxxxxxxxxxx'      # ← 换成你的知识库密钥
$aDataset = '906ffb78-4e8f-4cfe-b7c6-b93f0277efaf'   # ← 换成 A 的 UUID

$body = @{
  query = '防火分区最大允许建筑面积'
  retrieval_model = @{
    search_method = 'semantic_search'; reranking_enable = $false
    top_k = 3; score_threshold_enabled = $false; score_threshold = 0
  }
} | ConvertTo-Json -Depth 5

Invoke-RestMethod -Method Post -Uri "$base/datasets/$aDataset/hit-testing" `
  -Headers @{ Authorization = "Bearer $kbKey"; 'Content-Type' = 'application/json' } `
  -Body $body | ConvertTo-Json -Depth 6
```
- 通过判据：返回对象有 `records` 数组，每条含 `segment.content` 与 `score`。
- 首发 4xx 常见原因：base 少了 `/v1`；用成 app 密钥（应 `dataset-` 开头）；dataset_id 贴错。

> 说明：仓库 `scripts\windows-pwsh\` 目前**没有** `recall-compare` 的 pwsh 版（批量矩阵脚本 `recall-compare.sh` 是 Mac/zsh 版，见 `23-2` 第 5 章）。**现场 Windows 优先用 4a 浏览器召回测试**（跨平台、直观、能出对比截图）；确需批量矩阵时，可在讲师 Mac 上跑 `recall-compare.sh`（连本地或院内 Dify），或按上面 `Invoke-RestMethod` 手工逐题跑。

### 2.6 本章避坑清单

- hit-testing 用 `dataset-…` 密钥，不是 `app-…`。
- A/B 唯一变量只能是切分粒度：Embedding、检索方式、top_k、Rerank 开关必须完全一致；没配 rerank 就两边都别开。
- v1.11.2 无批量再索引：改分段/换 embedding 只能删档重传，界面没有「重新索引」按钮。
- 本语料 B 段少于 A 属正常（条文短）；看点是 B 把附注切散、溯源丢条文号。
- 索引卡「排队中」：院内 Dify 一般不会（embedding 已预置）；若自建本地 Dify，多为 embedding 接入地址容器内不通或 `weaviate` 没起。

---

## 3. 搭好后如何验证

> 规范问答助手（聊天助手/Agent，挂第 2 章知识库 A、开引用归属、院内 chat 模型）搭好后，在预览框逐条验证。
> 通过标准 = **答案正确 + 标了条号 + 能溯源 + 不瞎编**。

| 测试问题 | 期望答案 | 依据 |
|---|---|---|
| 多层民用建筑一个防火分区最大允许建筑面积？ | 不应大于 **2000㎡**（院内加严，国标 2500㎡） | 3.2.1 |
| 防火分区内全部设自动灭火系统时可增加多少？ | 可增加 **0.5 倍**（院内加严，国标 1.0 倍） | 3.2.1 注 |
| 消防电梯载重最低要求？ | 不小于 **1000kg**（院内加严，国标 800kg） | 6.3.2 |
| 本院设计文件编号规则？举例 | 专业代号-项目号-册号-版本号，示例 **JD-250137-03-V2** | 8.1.1 |
| （反面）消防电梯该选哪个品牌？ | 「院内规范未查到相关条文」，不给编造答案 | —— |

> 某题答错/漏条号/瞎编：优先回**指令**（三条铁律是否写清）与**检索设置**（召回条数/是否命中切片）排查，而非换模型。

---

## 4. 日常 AI 办公怎么用

> 规范问答助手发布后，业务人员的落地用法（6 步）：

1. **打开入口**：讲师/管理员点「发布」生成应用链接（或嵌入院内门户）；业务人员从 Dify「探索(Explore)」打开「规范问答助手」，或直接用分享链接。
2. **像聊天一样问**：对话框用大白话提问，例如「高层住宅疏散楼梯要用哪种？」。
3. **看依据再采信**：每条答案点开「引用来源」，核对命中的规范原文与条号，确认是院内加严/院内专有。
4. **带出处复制**：把「结论 + 依据条号」一起复制进设计说明、审校意见或答复函，做到有据可查。
5. **多轮追问**：继续追问「那国标是多少？」「这条适用地下室吗？」，助手记得上下文。
6. **沉淀入口**：把链接放进院内导航/浏览器收藏，作「随身规范顾问」，设计前查、审校时核。

---

## 5. 案例收集助手实操

> 应用类型：**聊天助手（Chatbot）**，对话访谈式填卡。全程不碰工作流（工作流留第四次课）。
> 只用「四件套」里的 **指令 + 记忆** 两样，**不挂知识库、不配工具**，最轻量。
> 出卡策略：**六字段答齐自动出卡 + 关键词「生成卡片/完成」兜底**。

### 5.1 实操前条件检查（三查，缺一不可）

**查 1：院内 DIFY 能打开、能登录**——浏览器开院内 Dify 地址，出现登录页或「工作室」，顶部有「工作室/知识库/工具」导航。
> 现场环境不自己起 Docker/Dify（院内已就绪）；只需确认能登录院内 Dify。

**查 2：至少一个大模型已接入且可用**——设置 → 模型供应商，至少一个供应商有可用的 **对话（Chat/LLM）** 类模型（院内已预置）。

**查 3（可选）：浏览器版本较新**——保证 Mermaid/Markdown 渲染正常（v1.11.2 刚修了 Mermaid XSS）。

> 现场小贴士：把「能登录院内 Dify + 有可用对话模型」做成投影上的绿勾清单，各组组长自查后举手，讲师再统一开始。

### 5.2 5 步搭建

```
1 建应用（聊天助手）→ 2 选大脑（模型+温度）→ 3 写访谈指令 → 4 调试走查 → 5 发布用
```

**第 1 步 · 建应用**：工作室 → 创建空白应用 → **聊天助手（Chatbot）**（蓝色对话气泡、副标题「简单配置即可构建基于 LLM 的对话机器人」那个）。
- ⚠️ 不要选 Chatflow（第四次课的工作流），也别选 Agent、文本生成、工作流。
- 名称填「案例收集助手」，描述「结项时逐项访谈、帮我填齐设计成果卡片」→ 创建。
- 验证：进「编排」页，能看到「指令编辑区 + 右上模型选择器 + 右侧调试与预览」三块 = 建对了。若看到画布/节点连线 = 误建成 Chatflow，删掉重建。

**第 2 步 · 选大脑**：右上模型选择器选院内对话模型；参数里**温度设 0.5–0.7**（比规范问答助手 0.1–0.3 略高，措辞自然但别太高偏离字段）。验证：模型名显示出来、预览框输「你好」能回话。

**第 3 步 · 写「访谈员」系统提示词（核心）**，原样粘贴到左侧「指令/提示词」区：

```
# 角色
你是一名"结项案例访谈员"，任务是帮机电/工程设计人员填写《设计成果卡片》。语气亲切、耐心，像一位熟悉流程的同事。

# 需要收集的六个字段（严格按此顺序）
1. 项目名称
2. 建设地点
3. 建筑规模
4. 主导专业
5. 技术难点
6. 可复用经验

# 访谈规则
- 一次只问一个字段，按上面顺序逐项提问，不要一次抛出多个问题。
- 每收到用户回答后，先用一句话简短复述你记下的内容（例如"好的，建设地点记为：上海"），再问下一个字段。这样用户能随时看到已收集内容。
- 如果用户回答"不清楚 / 还没定 / 暂时没有"之类，就把该字段记为"暂缺"，不要替用户编造，然后继续问下一项。
- 用户中途修改前面的答案时，以最新回答为准，并确认更新。
- 不要询问六个字段以外的信息。

# 输出成果卡片的时机
满足以下任一条件时，立即输出成果卡片：
（A）六个字段都已收集（含标记为"暂缺"的）；
（B）用户明确说"生成卡片""完成""出卡片""可以了"等表示结束的话。

# 成果卡片格式（用 Markdown 表格）
| 字段 | 内容 |
| --- | --- |
| 项目名称 | ... |
| 建设地点 | ... |
| 建筑规模 | ... |
| 主导专业 | ... |
| 技术难点 | ... |
| 可复用经验 | ... |

输出卡片后，加一句："以上是根据我们的对话整理的成果卡片，请核对；如需修改某一项，直接告诉我。"

# 开场
对话开始时，先做一句自我介绍，然后直接问第一个字段"项目名称"。
```

配上（可选但推荐）**对话开场白**（功能 → 打开「对话开场白」）：
```
你好，我是案例收集助手。结项恭喜！我按顺序问你 6 个问题，帮你把《设计成果卡片》填好。先问第一个——这个项目的项目名称是？
```
「下一步问题建议」可关闭，避免打断线性访谈。
- 验证：预览框点「重新开始/清空」后，助手主动发开场白且**只问「项目名称」一个问题** = 指令生效。

**第 4 步 · 调试走查**（演示项目脚本，讲师照着答）：

| 助手问 | 你答 |
|---|---|
| 项目名称？ | 某商业综合体改造项目 |
| 建设地点？ | 上海 |
| 建筑规模？ | 约 8 万㎡ |
| 主导专业？ | 机电 |
| 技术难点？ | **这个还没最终定**（← 故意答不清楚，测"暂缺"） |
| 可复用经验？ | 大空间排烟采用分区控制，机电管线综合排布经验可复用 |

四个验收点（对照打勾）：① 一次只问一项、按顺序问；② 缺项标「暂缺」不瞎编；③ 第六项答完**自动输出 Markdown 卡片**；④ 关键词兜底 + 可改（另起一轮，答到第三项时打「生成卡片」应立即出卡、未答字段标暂缺；出卡后说「把主导专业改成暖通」能更新重出卡）。
- 反面测试：中途问「顺便帮我算个防火分区面积」→ 期望它不跑题、礼貌拉回访谈。若「一次问一堆」或「自己编技术难点」→ 回第 3 步指令排查（漏了「一次一项」「不要编造」），不要靠换模型。

**第 5 步 · 发布 + 沉淀**：编排页右上「发布 → 更新/发布」→ 选「运行（公开访问 URL）」生成分享链接。每人填完把输出的 Markdown 卡片复制进院内案例库/共享文档。
- 验证：无痕窗口打开公开链接能开始全新访谈；卡片能粘进 Word/共享文档并保持表格。

### 5.3 记忆原理（讲给学员）

- **能记住**：同一会话里多轮追问，Dify 每接一句新问，都把之前全部问答（对话历史）连同系统指令一起发给大模型 → 模型每轮都「看得到」前面已说的字段。比喻：一个一直带着笔记本边聊边记的同事。
- **聊天助手没有「记忆」开关要打开**：记忆是对话型应用内建能力。你要做的是「确认 + 用好」，不是「开启」。
- **配置/用好记忆 = ① 选对应用类型（聊天助手）② 待在同一会话追问 ③ 用指令让助手每轮复述已收集内容 ④ 最后触发汇总出卡**。
- **三个边界**：① 新会话/点「重新开始」= 失忆（一张卡在一个连续会话里填完，演示别手滑清空）；② 上下文窗口有上限（6 字段对话很短，远够用，但天花板存在）；③ 记忆只在对话层，不自动入库（要沉淀仍需手动复制卡片，自动汇总入库是第四次课工作流的活）。

### 5.4 一页速查（贴墙）

| 步骤 | 关键动作 | 验证「成功长这样」 |
|---|---|---|
| 0 前置 | 能登录院内 Dify、模型通 | 两个绿勾 |
| 1 建应用 | 空白应用 → **聊天助手** → 命名 | 看到「指令+模型选择+预览」三块 |
| 2 选大脑 | 选模型，温度 0.5–0.7 | 预览框「你好」有回应 |
| 3 写指令 | 粘贴访谈员提示词 + 开场白 | 清空后只问「项目名称」 |
| 4 调试 | 演示项目走一遍 + 反面测试 | 一次一项/缺项暂缺/自动出卡/可改 |
| 5 发布 | 发布取公开链接 | 无痕窗口能全新访谈 |

---

> 来源整合：`wiki/08-2`（0 开工前必读、1.4 洗语料 PowerShell 段）、`wiki/18-1`、`wiki/20-1`（§2.3、§2.4）、`wiki/22-1`。Windows 现场无本地 Dify/ollama/bge-m3/代理修复内容（院内基础设施已就绪；那部分见 `23-2-hands-on-guide-for-mac-for-3rd-training.md`）。
