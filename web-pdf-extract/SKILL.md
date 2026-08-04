---
name: web-pdf-extract
description: |
  将网页抓取/导出的 PDF 文档（如技术文档、官方指南、白皮书等）转换为纯净 Markdown，
  自动剥离网页导航栏、页眉页脚、URL 水印、反馈链接、版权声明等网页噪音，
  提取并保存内嵌插图到 asset 文件夹，在文章开头自动生成摘要和标签。
tags: [pdf, markdown, extract, web-to-markdown, documentation, image-extraction]
---

# Web PDF Extractor — 网页 PDF 转纯净 Markdown

## 概述

本 skill 专门处理**从网页导出/抓取的 PDF 文件**（如官方技术文档、产品指南、白皮书等），将其转换为结构清晰、内容纯净的 Markdown 文档。

### 与 ppt-extract 的区别

| 维度 | ppt-extract | web-pdf-extractor |
|------|------------|-------------------|
| **输入来源** | PPT 演示文稿或从 PPT 转换的 PDF | 网页导出/打印的 PDF（文档类） |
| **内容特征** | 幻灯片式、大量图表、空间布局 | 长文本文档、段落、表格、代码块 |
| **核心任务** | 空间关系重建、图表结构化 | 网页噪音剥离、内容提纯 |
| **插图处理** | 每页截图（150 DPI）| 提取内嵌图片（原分辨率）|
| **OCR** | 辅助验证 | 通常不需要 |
| **输出结构** | 按幻灯片编号组织 | 按文档章节/标题层级组织 |

---

## 适用场景

- 将 Palantir、AWS、Azure 等技术文档的 PDF 归档为 Markdown
- 提取白皮书、官方指南等内容用于知识库构建
- 将网页打印的 PDF 还原为可编辑的文本格式
- 批量处理网页文档用于 RAG / AI 知识库

---

## 环境依赖

| 工具 | 用途 | 安装方式 |
|------|------|----------|
| `pdfplumber` (≥0.10) | PDF 文本提取（主通道） | `pip install pdfplumber` |
| `PyMuPDF` (fitz) | PDF 内嵌图片提取 | `pip install PyMuPDF` |
| `Pillow` | 图片格式处理 | `pip install Pillow` |

---

## 工作流程

### 第一步：准备输出目录

输出主文件夹与 PDF 文件同名（不含扩展名），放在 PDF 所在目录下。

```bash
PDF_FILE="{pdf_path}"
NAME="$(basename "$PDF_FILE" .pdf)"
OUTPUT_DIR="$(dirname "$PDF_FILE")/$NAME"
ASSET_DIR="$OUTPUT_DIR/asset"

mkdir -p "$ASSET_DIR"
```

最终输出结构：

```
{PDF所在目录}/{PDF文件名(不含扩展名)}/
├── {PDF文件名}.md              ← 纯净 Markdown 文档
└── asset/
    ├── page4_img1.png          ← 内嵌插图（按页码+序号命名）
    ├── page8_img1.png
    └── ...
```

### 第二步：提取文本内容

使用 pdfplumber 逐页提取文本：

```python
import pdfplumber

with pdfplumber.open(pdf_path) as pdf:
    for i, page in enumerate(pdf.pages, 1):
        text = page.extract_text()
        if text:
            # 逐段处理，剥离噪音
            cleaned_text = clean_web_noise(text)
            ...
```

> **⚠️ pdfplumber 为主通道**。如果 pdfplumber 提取为空（纯扫描件 PDF），则回退到 OCR 通道（参考 ppt-extract 的 OCR 流程）。

### 第三步：提取内嵌图片

使用 PyMuPDF 提取 PDF 中的内嵌图片：

```python
import fitz

doc = fitz.open(pdf_path)
for page_num in range(len(doc)):
    page = doc[page_num]
    image_list = page.get_images(full=True)
    for img_idx, img in enumerate(image_list):
        xref = img[0]
        base_image = doc.extract_image(xref)
        image_bytes = base_image["image"]
        ext = base_image["ext"]
        
        filename = f"page{page_num+1}_img{img_idx+1}.{ext}"
        filepath = os.path.join(asset_dir, filename)
        with open(filepath, "wb") as f:
            f.write(image_bytes)
        # 记录图片所在页码，供后续插入定位
        page_image_map[page_num + 1] = filepath
doc.close()
```

> **⚠️ 图片命名规则**：`page{N}_img{M}.{ext}`，其中 N 为页码，M 为该页图片序号（从 1 开始）。

### 第四步：剥离网页噪音

这是本 skill 的核心步骤。网页导出的 PDF 通常包含大量非内容元素，需要在提取文本后逐行/逐段清理。

#### 4a. 噪音识别清单

以下元素**必须**从 Markdown 输出中移除：

| 噪音类型 | 特征 | 处理方式 |
|---------|------|----------|
| **页眉导航栏** | 产品名 + "Search documentation" + "API Reference" 等 | 按行匹配并删除 |
| **面包屑/路径** | 如 "Ontology building / Ontology design: Best practices" | 仅保留最终标题，删除路径前缀 |
| **URL 水印** | 每页底部的完整 URL（`https://...`） + 页码（`X/19`） | 正则匹配 `https?://.*\d+/\d+$` 删除 |
| **时间戳** | 如 `8/4/26, 10:03 AM` 格式的打印时间 | 正则匹配日期时间模式删除 |
| **反馈链接** | 散布文中的 "Send feedback" 文字/链接 | 精确匹配删除（注意不误删正文中的 "feedback" 词） |
| **翻页导航** | "PREVIOUS" / "NEXT" + 箭头符号 | 精确匹配删除 |
| **页脚法律信息** | Copyright、Cookies、Privacy、Terms of Use 等 | 匹配并删除整段 |
| **Cookie 设置** | "Cookie Settings" 按钮文字 | 精确匹配删除 |
| **搜索框占位符** | "Search" + 搜索图标描述 | 匹配并删除 |
| **语言/版本切换器** | 如 "EN" "AB" "XY" 等短语言代码按钮 | 作为孤立短代码匹配删除 |

#### 4b. 噪音清理伪代码

```python
def clean_web_noise(text: str) -> str:
    """逐行清理网页导出 PDF 的噪音元素"""
    import re
    
    lines = text.split('\n')
    cleaned_lines = []
    
    for line in lines:
        stripped = line.strip()
        
        # 1. 跳过空 URL 水印行
        if re.match(r'^https?://.*/\d+/\d+$', stripped):
            continue
        
        # 2. 跳过 "Send feedback" 独立行
        if stripped == 'Send feedback':
            continue
        
        # 3. 跳过日期时间戳行 (如 "8/4/26, 10:03 AM ...")
        if re.match(r'^\d{1,2}/\d{1,2}/\d{2,4},\s*\d{1,2}:\d{2}\s*[AP]M', stripped):
            continue
        
        # 4. 跳过 PREVIOUS/NEXT 导航
        if stripped in ('PREVIOUS', 'NEXT', '←', '→', '← →'):
            continue
        
        # 5. 跳过页脚法律信息
        if re.match(r'^(©|Cookies|Privacy|Terms of Use|Cookie Settings)', stripped):
            continue
        
        # 6. 清理行内 "Send feedback" 后缀
        line = re.sub(r'\s*Send feedback\s*$', '', line)
        
        # 7. 清理行内 URL 水印
        line = re.sub(r'\s*https?://[^\s]+\d+/\d+\s*$', '', line)
        
        cleaned_lines.append(line)
    
    return '\n'.join(cleaned_lines)
```

> **⚠️ 注意事项**：
> - 清理顺序很重要：先识别整行删除，再进行行内替换
> - 每篇 PDF 的噪音模式可能略有不同，需要灵活调整正则表达式
> - **不要过度清理**：如果某行既包含噪音又包含内容，只删除噪音部分，保留内容

### 第五步：重建文档结构

#### 5a. 识别标题层级

根据字体大小、加粗、编号模式推断标题层级：

```
fontsize > 18pt + 粗体 + 独占一行  →  H1 (文章标题)
fontsize 14-18pt + 粗体 + 独占一行 →  H2 (章节标题)
fontsize 11-14pt + 粗体 + 独占一行 →  H3 (小节标题)
"数字. " 开头的加粗行               →  可能是设计原则/指南标题
```

#### 5b. 识别表格

pdfplumber 自动检测的表格保留为 Markdown 表格：

```python
tables = page.extract_tables()
for table in tables:
    # 转换为 Markdown 表格
    markdown_table = convert_to_markdown_table(table)
```

手动构建的对比表格（✗ Avoid / ✓ Prefer 模式）保持原样。

#### 5c. 重建引用块

识别文档中的核心原则陈述（通常为居中、加粗、较大字体），转换为 Markdown blockquote：

```markdown
> The Ontology models the real world, not the source data.
```

### 第六步：插入图片引用

根据图片在 PDF 中的页码位置，将其插入到 Markdown 文档中对应章节：

```markdown
![图片描述](asset/page4_img1.png)
```

**插入位置判断原则**：
- 图片通常出现在该章节引言段落之后、详细分点之前
- 如果该页同时有文字和图片，图片应放在本页文字段落的自然断点处
- 图片 alt text 应使用所在章节的标题或核心原则

### 第七步：生成摘要和标签

在 Markdown 文档开头生成全文元信息块，并对每个 `###` 级别的章节标题生成段落摘要。

#### 7a. 全文摘要和标签

```markdown
# {文档标题}

> **来源**: {来源说明，如 "Palantir Foundry 官方文档 — Ontology building / Ontology design: Best practices"}

## 摘要

{≤ 300 字的全文摘要，包含以下要素：}
- 第 1 句：文档类型和来源
- 第 2-4 句：核心论点和结构概述
- 最后一句：适用场景或目标读者

> **Tags**: `tag1` `tag2` `tag3` ... `tagN` (10-20 个标签，中英文混合)

---
```

#### 7b. 章节摘要（每个 `###` 标题）

对每个 `###`（三级标题，即文档的主要小节），紧跟标题行插入一句话摘要：

```markdown
### 1. Domain-driven design

> **📝 摘要**: 领域驱动设计要求 Ontology 建模真实世界的业务实体而非数据库表结构，避免 Kitchen Sink 反模式。

正文内容开始...
```

**章节摘要撰写原则**：
- **紧跟 `###` 标题**：摘要行紧接标题下，与 ppt-extract 的 `📝 摘要` 格式对齐，确保管道检索时能被正确提取
- **≤ 300 字**：与 ppt-extract 每页幻灯片摘要的字数限制一致
- **一句话概括**：说明本节的「核心主题 + 关键结论」
- **使用 blockquote 格式**：`> **📝 摘要**: {内容}`
- **文档级 `##` 标题**（如 Design guidelines、Pragmatism and tradeoffs）可选加摘要
- **四级标题 `####`**（如 Anti-patterns、Example、Best practices）不加摘要，由上层 `###` 摘要覆盖

---
```

**摘要撰写原则**：
- 覆盖全文核心内容，而非仅复述标题
- 突出文档的实用价值（谁应该读、能学到什么）
- 控制在 300 字以内

**标签选取原则**：
- 文档涉及的核心技术/产品（2-4 个）
- 文档涉及的核心概念/方法论（3-5 个）
- 文档类型（1-2 个，如 `最佳实践` `指南` `白皮书`）
- 设计模式/架构原则（2-4 个）
- 行业/领域（1-2 个）
- 总计 10-20 个，中英文混合

---

## 完整示例

### 输入

```
PDF 文件: Ontology design_ Best practices • Palantir.pdf
来源: https://www.palantir.com/docs/foundry/ontology/ontology-best-practices/
```

### 处理过程

```bash
# 1. 创建输出目录
mkdir -p "Ontology design_ Best practices • Palantir/asset"

# 2. 提取文本
python3 -c "
import pdfplumber
with pdfplumber.open('Ontology design_ Best practices • Palantir.pdf') as pdf:
    for i, page in enumerate(pdf.pages, 1):
        text = page.extract_text()
        # ... 清理噪音 ...
"

# 3. 提取图片
python3 -c "
import fitz
doc = fitz.open('Ontology design_ Best practices • Palantir.pdf')
# ... 提取内嵌图片到 asset/ ...
doc.close()
"

# 4. 组装 Markdown
# 将清理后的文本 + 表格 + 图片引用 + 摘要标签组装为最终 .md 文件
```

### 输出

```
Ontology design_ Best practices • Palantir/
├── Ontology design_ Best practices • Palantir.md
└── asset/
    ├── page4_img1.png
    ├── page8_img1.png
    ├── page11_img1.png
    └── page15_img1.png
```

---

## 输出质量标准

- [ ] 页眉导航栏、面包屑路径已全部移除
- [ ] 每页底部 URL 水印和页码已全部移除
- [ ] "Send feedback" 链接已全部移除
- [ ] PREVIOUS/NEXT 翻页导航已移除
- [ ] 页脚法律信息（Copyright/Cookies/Privacy/Terms）已移除
- [ ] 日期时间戳水印已移除
- [ ] 内嵌插图已提取到 asset 文件夹
- [ ] 图片引用路径正确（使用相对路径 `asset/`）
- [ ] 表格保留为 Markdown 表格格式
- [ ] 代码/术语使用反引号标注（如 `Patient`、`WorkOrder`）
- [ ] 文档开头有来源标注、全文摘要和标签
- [ ] 每个 `###` 章节标题下有 `> **📝 摘要**:`（≤300字），与 ppt-extract 格式一致
- [ ] 核心原则/金句使用 blockquote 突出
- [ ] ✗ Avoid / ✓ Prefer 对比表格正确渲染
- [ ] 整体结构层次分明（H1 → H2 → H3 → H4）
- [ ] **未误删正文内容**（噪音清理不会切掉正文段落）
- [ ] 输出语言为中文（摘要/标签/来源说明），正文保留原始语言

---

## 常见陷阱与规避

| 陷阱 | 表现 | 规避方式 |
|------|------|---------|
| **误删正文** | 噪音清理正则过于宽泛，把正文中类似模式删除 | 先识别独立行噪音，再处理行内噪音；每次清理后人工抽查 |
| **图片丢失** | pdfplumber 检测到图片但未提取；插图与文字不对应 | 使用 PyMuPDF 专门提取图片；记录图片所在页码，与文字内容对照定位 |
| **表格错乱** | pdfplumber 表格检测不完整（无边框表格、合并单元格） | 对照原文人工验证；复杂表格可考虑手动重建 |
| **标题层级混乱** | 字体大小信息不足以判断层级 | 结合编号模式（"1." "2."）、上下文位置、加粗特征综合判断 |
| **噪音残留** | 每篇文档的噪音模式不尽相同 | 先通读全文识别所有噪音模式，再编写清理规则；不要套用固定模板 |
| **过度清理** | 将 "Send feedback" 作为子串删除，误删正文中的 "Send feedback" | 仅删除独立的 "Send feedback" 行或后缀；用 `$` 锚定行尾 |
| **编码问题** | URL 编码的图片路径（%20 等）在某些 Markdown 渲染器中不工作 | 图片路径保留 URL 编码格式以确保跨平台兼容 |
| **章节摘要缺失** | 只生成了全文摘要，漏掉了每个 `###` 标题的摘要 | 遍历所有 `^### ` 标题确认每个都有对应的 `> **📝 摘要**:` 行；这直接影响 KG 检索时 `source_passages[].summary` 是否为空 |

---

## 使用方式

直接在对话中引用此 skill，并提供 PDF 文件路径：

```
/web-pdf-extractor {pdf_path}
```

或描述任务：

```
将这个 PDF 转换为纯净 Markdown，去掉网页导航等噪音，提取图片，加摘要和标签
```
