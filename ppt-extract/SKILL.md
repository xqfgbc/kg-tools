---
name: ppt-extract
description: |
  双通道 PPT/PDF 内容提取方法论。自动识别输入类型：
  - PPTX: 通道1(LibreOffice→PDF→PNG 150DPI+OCR) + 通道2(python-pptx 文本+坐标+形状)
  - PDF(从PPT转换): 通道1(PDF→PNG 150DPI+OCR) + 通道2(pdfplumber 文本+坐标+字体+表格)
  融合双通道数据重建关系，复杂图形以表格或多级列表呈现。
tags: [ppt, pdf, ocr, extraction, methodology, documentation]
---

# PPT 内容提取方法论

## 概述

本 skill 提供一套从 PPTX 或 PDF（已从 PPT 转换）文件中提取内容和结构关系的完整方法论。

### 输入类型自动判断

| 输入格式 | 判断依据 | 通道策略 |
|---------|---------|---------|
| **PPTX** (.pptx) | 文件扩展名 | 通道1: LibreOffice→PDF→PNG+OCR / 通道2: python-pptx（文本+坐标+形状+GROUP递归） |
| **PDF** (.pdf) | 文件扩展名，且确认为 PPT 转换而来 | 通道1: PDF→PNG+OCR（跳过LibreOffice）/ 通道2: pdfplumber（文本+坐标+字体+表格+图形） |

> **⚠️ PDF 输入判断**：如果 PDF 是通过 LibreOffice/PPT 另存为等从 PPT 转来的（而非扫描件），可以直接使用 PDF 双通道。典型特征：页数较多（10+）、内容为幻灯片风格、无扫描噪点。

### 双通道互补策略

无论是 PPTX 还是 PDF 输入，均遵循**双通道互补**原则：

1. **图片通道**: PDF → pdftoppm (150 DPI) → PNG + Tesseract OCR
2. **结构化通道**: 
   - PPTX: python-pptx 直接提取（文本+坐标+形状类型+连接线+GROUP递归）
   - PDF: pdfplumber 提取（文本+坐标+字体大小+表格+图形元素）

两通道数据融合后，人工编排重建 PPT 中的逻辑关系，最终产出结构化 Markdown 文档。

---

## ⚠️ 核心原则：结构化内容原样呈现

**对于 PPT 中结构化内容的转换，严禁进行总结、提炼或主观解读，必须如实反映原始内容。输出语言使用中文。** 具体要求：

- **如实翻译**：将 PPT 原始内容（通常为英文）忠实翻译为中文，逐句对应，不增删改。这不是总结提炼，而是在不改变原意前提下的语言转换
- **禁止**：对 PPT 页面中的结构化内容（文本、图表、流程等）进行总结、概括、提炼或用自己的话重新表述
- **禁止**：在结构化内容区域添加 PPT 中不存在的主观评论、推断或解读
- **允许**：将 PPT 中复杂图形（如流程图、关系图、架构图）转换为**表格或多级列表**以呈现其结构化信息——这是格式转换，不是内容提炼
- **允许**：标注内容的坐标位置、形状类型等元数据以帮助理解空间关系
- **允许**：在表格中同时保留中英文对照（如关键术语、指标名称），方便读者对照原始 PPT
- **输出语言**：正文使用中文输出；专业术语如产品名（Dynatrace、ServiceNow）、技术名（MELT、MCP）、指标名（MTTD、MTTR）保留英文原文

> **注意**：每页的「📝 摘要」和全文的「📋 总体概要」以及「🏷️ 标签」**不受本条规则限制**——这些辅助性描述可以对内容进行概括和提炼。

---

## 适用场景

- 从 PPT 中提取内容用于文档化、知识管理
- 分析咨询/战略类 PPT 的结构和逻辑
- 提取包含复杂图表、关系图、演化路径的演示文稿
- 需要保留 PPT 中视觉关系（空间布局、连接线、层级结构）

---

## 环境依赖

| 工具 | 用途 | 安装方式 |
|------|------|----------|
| `LibreOffice` (≥26.x) | PPTX → PDF 转换 | `brew install --cask libreoffice` 或手动下载 DMG。路径配置见 `config.sh` 中的 `LIBREOFFICE_PATH` |
| `pdftoppm` (poppler) | PDF → PNG 转换 | `brew install poppler` |
| `tesseract` (≥5.x) | OCR 文字识别 | `brew install tesseract` + `tesseract-lang` (中文包) |
| `python-pptx` | PPTX 结构化提取 | `pip install python-pptx` |
| `pdfplumber` (≥0.10) | **PDF 结构化提取**（文本+坐标+表格+字体） | `pip install pdfplumber` |
| `Pillow` | 图片元数据读取 | `pip install Pillow` |

---

## 工作流程

### 第零步：判断输入类型，选择通道策略

```bash
# 根据文件扩展名判断
if [[ "{input_file}" == *.pptx ]]; then
  INPUT_TYPE="pptx"
elif [[ "{input_file}" == *.pdf ]]; then
  INPUT_TYPE="pdf"
else
  echo "❌ 不支持的文件格式: {input_file}"
  exit 1
fi
echo "📋 输入类型: $INPUT_TYPE"
```

> **PDF 输入**：跳过 LibreOffice 转换步骤（第二步-图片通道中跳过 2a），直接从 2b（PDF→PNG）开始。结构化通道使用 pdfplumber 替代 python-pptx。

### 批量模式：处理整个文件夹

当输入是**文件夹**而不是单个文件时，**不要手写循环——直接调脚本**。

```bash
# 提取（PPTX→PDF→PNG→结构化提取）
bash "{skill_dir}/batch_extract.sh" "{输入文件夹}" [更多目录...]

# OCR（辅助验证，可后补、可与撰写并行）
bash "{skill_dir}/batch_ocr.sh" "{输入文件夹}" [更多目录...]
```

两个脚本都幂等：已完成的产物会跳过，中断后重跑即可续上。

**为什么必须是脚本而不是 SKILL 里的内联片段**：这几步踩过两个会**静默出错**的坑，
都是照抄片段时才会发生的——

| 坑 | 症状 | 脚本里的处理 |
|---|---|---|
| `printf -v new "slide_%02d.png" "$n"` 把前导 0 当八进制 | `08`/`09` 非法 → 都输出 `slide_00.png` → 第 8、9 页图片被覆盖丢失，**脚本不报错**（zsh 里反而正常，极难发现） | 用 `"$((10#$n))"` 强制十进制，并在末尾自检编号连续性 |
| 手抄源文件名 | 文件名含 U+00A0 不换行空格时匹配不上，**整份文档被静默跳过** | 待处理清单从 `find` **枚举**，绝不手抄 |

**Step: 撰写**

提取完不等于完成——还差最后一步：按**第六步**把 `extraction_raw.txt` 撰写成
`{name}.md`。该步骤的完整规范（铁律、单页模板、文档骨架、格式约定、
图形式页面的阅读要求、输出质量标准）见：

```
{skill_dir}/AUTHORING_BRIEF.md
```

**Step: 批量质量检查**

```bash
for dir in "{输入文件夹}"/*/; do
  name="$(basename "$dir")"
  md="$dir$name.md"
  [ -f "$md" ] || { echo "❌ 缺产物: $name"; continue; }
  echo "✅ $name — slides=$(grep -c '^## Slide' "$md") imgs=$(ls "$dir/asset" 2>/dev/null | wc -l | tr -d ' ') md=$(grep -c '!\[Slide' "$md")"
done
```

`slides`、`imgs`、`md`（图片引用数）三者应**相等**且等于源 PPT 页数。

### 第一步：准备输出目录

> **命名规则**：输出主文件夹使用文件名（去掉扩展名）命名，放在文件所在目录下。

```bash
# {name} = 文件名（不含扩展名）
# {output_dir} = {文件所在目录}/{name}/
mkdir -p "{output_dir}/asset"
```

输出结构：
```
{文件所在目录}/{name}/           ← 主文件夹以文件名命名
├── {name}.md                   ← 最终 Markdown 文档
├── {name}.pdf                  ← 中间产物 (仅PPTX输入时生成)
├── extract_pdf.py              ← PDF提取脚本 (仅PDF输入时生成)
├── extraction_raw.txt          ← 结构化提取原始输出
└── asset/
    └── slide_01.png ...        ← 每页幻灯片的高清图片
```

### 第二步：图片通道（PDF → PNG + OCR）

> **⚠️ 关键分支**：PPTX 输入需先经 LibreOffice 转为 PDF（步骤 2a），PDF 输入直接从 2b 开始。

```bash
# 2a. [仅PPTX输入] PPTX → PDF
# 加载配置文件
source "{skill_dir}/config.sh"

# 查找 LibreOffice (优先使用 config.sh 配置的路径)
SOFFICE_PATH=""
if [ -n "$LIBREOFFICE_PATH" ] && [ -f "$LIBREOFFICE_PATH/Contents/MacOS/soffice" ]; then
  SOFFICE_PATH="$LIBREOFFICE_PATH/Contents/MacOS/soffice"
else
  # 回退: 搜索系统路径
  for p in "/Applications/LibreOffice.app/Contents/MacOS/soffice"; do
    [ -f "$p" ] && { SOFFICE_PATH="$p"; break; }
  done
  [ -z "$SOFFICE_PATH" ] && SOFFICE_PATH=$(mdfind -name "soffice" 2>/dev/null | grep -m1 "LibreOffice.*soffice$")
fi

if [ "$INPUT_TYPE" = "pptx" ]; then
  [ -z "$SOFFICE_PATH" ] && { echo "❌ LibreOffice soffice 未找到，请检查 config.sh 中的 LIBREOFFICE_PATH"; exit 1; }
  echo "✅ 使用 soffice: $SOFFICE_PATH"
  "$SOFFICE_PATH" --headless --convert-to pdf \
    --outdir "{output_dir}" "{input_path}"
fi

# 2b. PDF → PNG (150 DPI，兼顾文件大小和清晰度)
# 150 DPI 足够 OCR 识别和阅读，文件大小约为 300 DPI 的 1/4
pdftoppm -png -r 150 "{pdf_path}" "{output_dir}/asset/slide"
```

> **注意**: pdftoppm 输出的文件名为 `slide-1.png`, `slide-2.png`...，需重命名为 `slide_01.png` 统一格式。

```bash
# 2c. 重命名为 slide_NN.png
# ⚠️ 必须用 10#$n 强制十进制，否则会静默丢图。
# pdftoppm 按总页数补零（>9 页时输出 slide-08.png）。bash 的 printf %d 把前导 0 当八进制，
# "08"/"09" 是非法八进制 → 报 "invalid number" 并按 0 处理 → 两次都输出 slide_00.png，
# 第二个把第一个覆盖掉。结果：第 8、9 页图片凭空消失，而 md 里的
# ![Slide 8](asset/slide_08.png) 指向不存在的文件，且脚本不会报错。
# （zsh 的 printf 不这么做 —— 同一段代码在 zsh 里跑反而正常，极易漏过。）
( cd "{output_dir}/asset" && for p in slide-*.png; do
    [ -e "$p" ] || continue
    n="${p#slide-}"; n="${n%.png}"
    printf -v new "slide_%02d.png" "$((10#$n))"
    [ "$p" = "$new" ] || mv "$p" "$new"
  done )
```

**改完必须核对**：图片编号应连续无缺口，且数量等于页数。

```bash
ls "{output_dir}/asset"/slide_*.png | wc -l          # 应等于 PPT 页数
ls "{output_dir}/asset" | grep -E '^slide-|slide_0*0\.png'   # 应无输出
```

### 第三步：结构化通道

> **⚠️ 关键分支**：根据输入类型选择不同的提取脚本。PPTX 用 python-pptx，PDF 用 pdfplumber。

#### 3A. PPTX 输入：python-pptx 提取

> **⚠️ 关键：直接使用 skill 目录下的 `extract_pptx.py` 脚本，不要手写简化版。该脚本已内置 GROUP 递归，避免遗漏嵌套内容。**

> **⚠️ Python 环境**：必须使用 `config.sh` 中配置的 `PDFPLUMBER_PYTHON`（该环境同时装有 python-pptx），不要用裸 `python3`——默认 `python3` 指向的可能是未安装 python-pptx 的环境。

```bash
# 加载配置获取解释器路径
source "{skill_dir}/config.sh"

# 使用 skill 自带的 extract_pptx.py 脚本
"$PDFPLUMBER_PYTHON" "{skill_dir}/extract_pptx.py" "{pptx_path}" > {output_dir}/extraction_raw.txt 2>&1
```

**关键提取维度**：

| 维度 | 提取内容 | 用途 |
|------|----------|------|
| 所有带文本的形状（递归进入 GROUP） | 文本 + 坐标(x,y,w,h) + 嵌套层级 | 内容主体 |
| LINE/CONNECTOR | 起点+终点坐标 | 连接关系 |
| TABLE | 所有行列文本 | 表格数据 |
| PICTURE | 坐标+尺寸 | 嵌入图片标记 |

#### 3B. PDF 输入：pdfplumber 提取

> **⚠️ Python 环境**：使用 `config.sh` 中配置的 `PDFPLUMBER_PYTHON`，该 Python 需已安装 pdfplumber。

将 skill 目录下的 `extract_pdf.py` 复制到输出目录并运行：

```bash
# 加载配置获取 PDFPLUMBER_PYTHON
source "{skill_dir}/config.sh"

# 使用 skill 自带的 extract_pdf.py 脚本
cp "{skill_dir}/extract_pdf.py" "{output_dir}/extract_pdf.py"
"$PDFPLUMBER_PYTHON" "{output_dir}/extract_pdf.py" "{pdf_path}" > {output_dir}/extraction_raw.txt 2>&1
```

> **⚠️ 关键：直接使用 skill 目录下的 `extract_pdf.py` 脚本，不要手写简化版。**

**pdfplumber 提取维度**：

| 维度 | 提取内容 | 用途 |
|------|----------|------|
| TEXT LINES（按阅读顺序） | 文本 + 坐标(x,y,w,h) + 字体名 + 字体大小 | 内容主体 + 标题/正文层级判断 |
| TABLES（自动检测） | 所有行列文本（二维字符串数组） | 表格数据 |
| FONTS（统计分布） | 字体-大小组合及其出现频率 | 辅助判断标题、正文、注释的层级 |
| GRAPHICS（矩形/线条） | 矩形坐标+大小、线条数量 | 辅助判断内容区域边框和布局 |

**PPTX vs PDF 通道对比**：

| 能力 | python-pptx (PPTX输入) | pdfplumber (PDF输入) | 说明 |
|------|----------------------|---------------------|------|
| 文本提取 | ✅ 高精度 | ✅ 高精度 | 两者均接近 100% |
| 文本坐标 | ✅ EMU 级 (x,y,w,h) | ✅ pt 级 (x,y,w,h) | 精度相当 |
| 形状类型 | ✅ GROUP/LINE/TABLE/PICTURE | ⚠️ 仅 RECT/LINE | PDF 通道形状信息有限 |
| GROUP 递归 | ✅ 内置递归 | N/A | PDF 无 GROUP 概念 |
| 连接线 | ✅ 起点+终点 | ❌ 不支持 | PDF 通道缺失 |
| 表格 | ✅ 精确行列 | ✅ 自动检测 | PDF 通道通过视觉检测表格 |
| 字体信息 | ✅ 字体名+大小 | ✅ 字体名+大小 | 均可辅助判断层级 |
| 图片内文字 | ❌ 不支持 | ❌ 不支持 | 均需 OCR 通道补充 |

### 第四步：OCR 识别（辅助验证）

```bash
# 对每张图片执行 OCR
tesseract "{output_dir}/asset/slide_{i:02d}.png" \
  "{output_dir}/ocr_slide_{i:02d}" -l chi_sim+eng
```

> **注意**: OCR 准确率约 85-90%（中英混合密集文本会更低），仅作为结构化提取的辅助验证，不作为主数据源。

### 第五步：关系重建

这是最关键的步骤。将步骤 3 和 4 的数据融合，重建 PPT 的逻辑结构。

> **⚠️ PDF 输入注意**：pdfplumber 通道没有形状类型（GROUP/LINE/CONNECTOR），需依赖坐标聚类 + OCR 图片验证来推断关系。

#### 5a. 按坐标分区域

```
根据 y 坐标判断垂直层级:
  y < 2.0     → 顶部区域 (标题/总览)
  2.0 < y < 4.0 → 中部区域
  y > 4.0     → 底部区域 (基础/传统)

根据 x 坐标判断水平位置:
  x < 3.0     → 左侧列
  3.0 < x < 7.0 → 中间列
  x > 7.0     → 右侧列 (目标/成果)

[PDF通道] 字体大小辅助判断:
  fontsize > 20pt → 标题
  14pt < fontsize < 20pt → 副标题/节标题
  10pt < fontsize < 14pt → 正文
  fontsize < 10pt → 注释/脚注
```

#### 5b. 按语义聚类

将散落的文本点按主题聚合成能力线/路径：
- 知识类 → 知识演进路径
- 监控/可观测性类 → 可观测性演进路径
- 自动化/AI类 → 自动化演进路径
- 架构类 → 架构演进路径
- 运维类 → 智能运维路径

#### 5c. 识别连接线与阶段分隔

- **[PPTX]** LINE/CONNECTOR 连接的形状 → 父子/从属关系
- **[PPTX]** Freeform 色带 → 阶段划分依据
- **[PPTX]** GROUP 内的子元素 → 逻辑分组
- **[PDF]** 表格结构 (pdfplumber TABLES) → 行列数据关系
- **[PDF]** 坐标相邻 + 字体大小一致 → 同组关系
- **[PDF+OCR]** OCR 图片验证文本 → 交叉参考

### 第六步：编写结构化 Markdown

> **本步的完整规范已固化在 `{skill_dir}/AUTHORING_BRIEF.md`**（铁律、单页模板、
> 文档骨架、格式约定、图形式页面的阅读要求、输出质量标准）。
> 下面的 6a–6d 是同一套约定的展开说明，二者应保持一致。
>
> 这一步是**格式转换 + 忠实翻译**，不是总结提炼——这是最容易做错的地方，
> 动手前先读 brief 里的「铁律」一节。

#### 6a. 生成每页幻灯片的描述与标签

对每一页幻灯片，在内容解析完成后生成：

```markdown
## Slide N: {标题}

![Slide N](asset/slide_NN.png)

> **📝 摘要**: {不超过300字的描述，概括本页核心内容和要点}

> **🏷️ 标签**: `标签1` `标签2` `标签3` ... （不超过10个）

---

{结构化内容解析}
```

**描述撰写原则**：
- 用 2-4 句话概括：主题 → 核心论点 → 关键结论
- 如果幻灯片包含多区域内容，点明各区域之间的关系
- 不要简单重复标题，要提取「这张 PPT 想传达什么」
- 严格控制在 300 字以内

**标签选取原则**：
- 反映幻灯片的领域（如 `AIOps` `Observability`）
- 反映内容类型（如 `蓝图` `路线图` `案例` `指标`）
- 反映涉及的技术/方法（如 `AgenticAI` `KnowledgeGraph`）
- 反映阶段/层级（如 `Modernize` `Strategic`）
- 不超过 10 个

**标签禁用词**（不要出现在标签中）：
- `埃森哲` `Accenture` `accenture` — 公司/品牌名称
- `目录` — 目录页的通用描述
- `分隔页` — 章节分隔页的通用描述

#### 6b. 生成整个 PPT 的总体描述与标签

在文档开头，封面页之后、目录之前：

```markdown
# {PPT 标题} — PPT 解析文档

> **原始文件**: `{filename}` | **页数**: {N} 页 | **日期**: {date}

## 📋 总体概要

| 项目 | 内容 |
|------|------|
| **摘要** | {不超过300字的整体描述，概括PPT的主题、目标受众、核心叙事逻辑和关键结论} |
| **标签** | `tag1` `tag2` ... `tagN` (≤10个) |
| **章节结构** | {章节列表} |

---

## 幻灯片目录
...
```

**总体描述撰写原则**：
- 第 1 句：这份 PPT 是什么（类型 + 主题）
- 第 2-3 句：核心叙事逻辑（如何组织、主要论点）
- 第 4 句：关键结论或目标受众
- 严格控制在 300 字以内

**总体标签选取原则**：
- 覆盖 PPT 的核心领域（2-3 个）
- 覆盖涉及的技术/方法（2-3 个）
- 覆盖 PPT 类型（策略/蓝图/案例/评估 等，1-2 个）
- 覆盖行业/场景（如 `金融` `零售` `IT运维`，1-2 个）
- 覆盖阶段/层级（如 `战略` `执行` `转型`，1-2 个）
- 不超过 10 个
- **标签禁用词同上**：不要使用 `埃森哲` `Accenture` `accenture` `目录` `分隔页`

#### 6c. 格式约定

1. **输出语言**: 使用中文输出（专业术语如产品名/技术名保留英文原文，必要时附加中文说明）
2. **简单列表** → 无序/有序列表
2. **对比关系** → 表格
3. **层级结构** → 多级列表或嵌套表格
4. **流程/路径** → 表格（包含步骤序号、阶段、能力项、坐标、说明列）
5. **演化/递进** → 总表 + 分路径详表
6. **汇总对比** → 横向对比总表
7. **每页必须附带** → 原始 PPT 该页的高清图片

#### 6d. 文档完整模板结构

```markdown
# {PPT 标题} — PPT 解析文档

> **原始文件**: `{filename}` | **页数**: {N} 页 | **解析方式**: {方法说明}

## 📋 总体概要
| 项目 | 内容 |
|------|------|
| **摘要** | {≤300字整体描述} |
| **标签** | `tag1` `tag2` ... |

## 幻灯片目录
| # | 标题 / 章节 | 内容概要 |
|---|------------|----------|

---

## Slide 1: {标题}
![Slide 1](asset/slide_01.png)
> **📝 摘要**: {≤300字}
> **🏷️ 标签**: `t1` `t2` ...
{结构化内容}

---

## Slide 2: {标题}
...

---

## 附录：OCR 原始输出
{OCR 文本}
```

---

## 输出质量标准

- [ ] **输出语言为中文**（专业术语保留英文原文，必要时附加中文说明）
- [ ] 每个表格都标注了列的含义
- [ ] **[PPTX]** 坐标数据（来自 python-pptx）与 OCR 文本交叉验证，不一致处已标注
- [ ] **[PDF]** 坐标数据（来自 pdfplumber）与 OCR 文本交叉验证，不一致处已标注
- [ ] **[PDF]** pdfplumber 检测到的表格已全部纳入 Markdown 表格/列表
- [ ] 关系描述有明确的结构依据（坐标相邻、语义相关、[PPTX]连接线连接、[PDF]表格结构）
- [ ] 没有编造 PPT 中不存在的内容
- [ ] 复杂图形已转换为表格或多级列表
- [ ] 图片引用路径正确
- [ ] 中英文术语保留原文，必要时附加中文说明
- [ ] 每页幻灯片都包含原始图片引用
- [ ] 每页幻灯片都有 ≤300 字的摘要描述
- [ ] 每页幻灯片都有 ≤10 个标签
- [ ] 文档开头有总体概要（≤300 字描述 + ≤10 标签）
- [ ] 标签准确反映内容领域、类型、技术方法和阶段
- [ ] 标签不包含禁用词（埃森哲、Accenture、accenture、目录、分隔页）
- [ ] **结构化内容区域原样呈现 PPT 原文，无总结提炼**（摘要和总体概要除外）

---

## 常见陷阱与规避

| 陷阱 | 表现 | 规避方式 |
|------|------|---------|
| **纯 OCR 做主数据源** | 文字错乱、结构丢失 | OCR 仅辅助验证，结构化提取为主 |
| **忽略坐标信息** | 无法还原空间关系 | 所有文本必须记录 (x,y) 坐标 |
| **扁平化输出** | 把所有文本混为一堆 | 先按 y 分层、再按 x 分列、最后语义聚类 |
| **忽略小形状** | Oval/Freeform/LINE 被跳过 | 显式遍历所有形状类型 |
| **忽略 GROUP 内部文本** | 只提取了顶层形状的文本，GROUP 内的子形状文本被遗漏，导致输出内容大量缺失 | 对 GROUP 形状递归遍历子形状，提取所有嵌套文本；这是双通道提取中最容易被忽视的关键步骤 |
| **编造内容** | 添加 PPT 中没有的推论 | 所有内容必须有来源（坐标/OCR/形状） |
| **对内容进行提炼改写** | 将 PPT 原文用自己的话重新表述，丢失原始表达 | 结构化内容区域严格使用 PPT 原文，仅做格式转换（文本→表格/列表），不做内容改写 |
| **复杂图简单化** | 用文字段落描述复杂关系 | 强制转换为表格或多级列表 |
| **LibreOffice 路径问题** | soffice 命令找不到 | macOS 上需使用完整路径或从 DMG 直接运行 |
| **[PPTX/PDF] 用错 Python 环境** | `ModuleNotFoundError: No module named 'pdfplumber'` 或 `No module named 'pptx'` | 检查 `config.sh` 中的 `PDFPLUMBER_PYTHON` 配置，确保该 Python 已装齐 pdfplumber + python-pptx；不要用裸 `python3` |
| **config.sh 缺失** | `source: no such file or directory: .../config.sh` | 首次使用需先运行 `bash {skill_dir}/setup.sh` 生成 config.sh；若本机 Python 无 pip，改用 `uv pip install --python <解释器> pdfplumber` 后手工创建 config.sh |
| **[PDF] 表格漏检** | pdfplumber 表格检测不完整（复杂嵌套表格、无边框表格） | 对照 OCR 输出和 PNG 图片人工验证，用坐标+字体信息手动重建表格 |
| **[PDF] 架构图乱码** | 密集图表区域 pdfplumber 文本行列交错、不可读 | 降级依赖 OCR 通道，以 PNG 图片为最终参考 |
| **[PDF] 误判为非PPT文件** | 将扫描版 PDF 或常规文档 PDF 当做 PPT 处理 | 使用前确认 PDF 来源：页数多（10+）、幻灯片风格布局、无明显扫描噪点 |
| **批量模式喂进 Office 临时文件** | LibreOffice/pdfplumber 对 `~$xxx.pptx` 报错或产出空结果 | 用 `find ... ! -name '~$*'` 过滤 |
| **批量重跑把已完成的工作覆盖掉** | 重复消耗大量时间重做已完成的文档 | 开工前用 Step 2 的 mtime 判定跳过；确认要重做时才设 `FORCE=1` |
| **文件名含空格导致循环出错** | 变量被拆成多个词 | 所有变量展开都加双引号：`"$f"`、`"$(dirname "$f")"` |
| **用 `mapfile` / 数组** | macOS 自带 `/bin/bash` 是 3.2，不支持 `mapfile` | 用 `while IFS= read -r f; do ... done < "$LIST"` 的写法（SKILL 中的片段已按此编写） |
| **PNG 重命名静默丢图** | `printf: 08: invalid number`，第 8、9 页图片消失、多出 `slide_00.png`，但脚本不报错 | 用 `printf -v new "slide_%02d.png" "$((10#$n))"` 强制十进制（见 2c）；改完必须核对编号连续、总数等于页数 |
| **文件名含不换行空格 U+00A0** | 手写 `"SaaS _PS"`（普通空格）匹配不到实际的 `SaaS\xa0_PS.pptx`，整份文档被静默跳过 | 待处理清单从**文件系统枚举**，不要手抄文件名；用 `python -c "print(repr(name))"` 确认异常字符 |
| **两个批量任务同时跑** | 各自启动 LibreOffice 写同一输出目录，产物互相覆盖；日志里看不出异常 | `batch_extract.sh` 已加载全局锁（`/tmp/ppt-extract-batch.lock`），第二个实例会被拒绝 |
| **中断留下半截 PDF 被当成「已完成」** | 只判断 `[ -f ...pdf ]`，于是下次运行跳过转换，pdftoppm 直接失败或产出残缺 | 用 `pdfinfo` 取页数校验 PDF 有效性；页数为空则重新转换；末尾再断言 PNG 数 == PDF 页数 |
| **`$var` 紧跟中文导致 unbound variable** | `echo "有 $have，"` 中的全角逗号被 bash 当作变量名的一部分 → `have，: unbound variable` | 变量后紧跟非 ASCII 字符时必须用 `${var}` 界定 |
| **仅凭 `ls \| wc -l` 判断图片齐全** | 重命名 bug 丢页后总数仍可能是「对的」（多一个 `slide_00.png` 补上了缺口） | 断言**编号连续无缺口**且**等于 PDF 页数**，而不只是数个数 |
| **产物目录判据依赖 `.md`，导致目录无限嵌套** | 用 `{name}/{name}.md` 是否存在来判断「这是不是提取产物目录」。但撰写在提取之后，`.md` 尚未生成时判据失效 → `{name}.pdf` 被当成新源文件 → 写进 `{name}/{name}/` → 下次再扫又发现更深一层。**每跑一次多嵌套一层**，并重复消耗磁盘与时间 | 判据用「存在 `{name}.pdf`」+「存在 `extraction_raw.txt` 或 `asset/`」，**不要依赖 `.md`**。发现嵌套后删除同名子目录即可，源文件不受影响 |
| **DRM/IRM 加密的文件** | 文件是 OLE2 但**没有 `PowerPoint Document` 流**，真实内容在 `EncryptedPackage` 流里（Microsoft Purview / Azure 信息保护等）。LibreOffice **不支持 IRM**：转换不报错，而是 100% CPU **空转十几分钟、零产出**，看起来像「文件大所以慢」 | 用 `is_drm_protected()` 提前识别并跳过。**不要尝试绕过加密**，需有权限的账号在 PowerPoint 中导出未加密副本 |
| **文件扩展名与实际格式不符** | 老式二进制 `.ppt` 被改成 `.pptx`：LibreOffice 能转 PDF，但 python-pptx 打不开 zip，结构化通道直接失败 → 产出一堆 PNG 却无可读内容 | 按**魔数**判断格式（`d0cf11e0`=OLE2 / `504b0304`=OOXML / `25504446`=PDF），老式 `.ppt` 先转成真 `.pptx` 再走结构化通道（比退回 PDF 通道质量高） |

---

## 使用示例

### PPTX 输入

```
解析 "{pptx_file}"，将每页内容先通过 LibreOffice 导出成图片，
再用 OCR 解析内容。要注意 PPT 中内容之间的关系。
```

### PDF 输入

```
解析 "{pdf_file}"，该 PDF 已从 PPT 转换，跳过 LibreOffice 步骤，
直接用 pdfplumber 做结构化提取，再用 OCR 辅助验证。
```

### 文件夹输入（批量）

```bash
bash "{skill_dir}/batch_extract.sh" "{input_dir}"      # 提取
bash "{skill_dir}/batch_ocr.sh"     "{input_dir}"      # OCR（可选）
```

脚本逐份串行处理，幂等可续跑；随后按 `AUTHORING_BRIEF.md` 逐份撰写 `{name}.md`。

> 输出目录**沿用单文件规则**（`{文件所在目录}/{name}/`），源文件夹下会多出
> 每个文档一个子目录。整条入库链路（`kb-ingest`）用的就是这个批量约定。

### 预期输出

```
{文件所在目录}/{文件名}/          ← 主文件夹以文件名命名
├── {name}.md                   ← 结构化解析文档
├── {name}.pdf                  ← 中间产物 (仅PPTX输入时生成)
├── extract_pdf.py              ← PDF提取脚本 (仅PDF输入时生成)
├── extraction_raw.txt          ← 结构化提取原始输出
└── asset/
    ├── slide_01.png            ← PNG 图片 (150 DPI, ~2000px宽)
    └── slide_02.png ...
```

### 质量检查

- [ ] Markdown 中嵌入了每页幻灯片的图片
- [ ] 复杂图形以表格形式呈现
- [ ] 关系描述有坐标/形状数据支撑（PPTX: python-pptx; PDF: pdfplumber）
- [ ] 无编造内容
- [ ] 每页有 ≤300 字的摘要描述 + ≤10 个标签
- [ ] 文档开头有总体概要（≤300 字 + ≤10 标签）
- [ ] 文档开头有幻灯片目录表
- [ ] [PDF] pdfplumber 检测到的表格已全部转换为 Markdown 表格
- [ ] [PDF] 文本坐标数据已用于空间关系推断
