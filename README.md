# KG Tools — 知识库工具链

AI/IT 运维知识库的完整工具链，覆盖「PPT/PDF 提取 → Obsidian 融入 → 知识图谱构建 → 问答检索」全流程。本仓库为 Claude Code Skill 定义的权威来源。

## 仓库结构

```
kg-tools/
├── README.md
├── .gitignore
├── ppt-extract/               ← PPT/PDF 双通道提取（含实现脚本）
│   ├── SKILL.md
│   ├── extract_pptx.py        # PPTX 结构化提取
│   ├── extract_pdf.py         # PDF 结构化提取
│   ├── setup.sh               # 环境安装脚本
│   └── config.example.sh      # 配置模板（config.sh 不提交）
├── web-pdf-extract/           ← 网页 PDF 转纯净 Markdown
│   └── SKILL.md
├── addToObsidian/             ← 提取内容融入 Obsidian Vault
│   └── skill.md
├── kg-update/                 ← 知识图谱增量更新
│   └── SKILL.md
└── kg-qa/                     ← 知识图谱问答检索
    └── SKILL.md
```

## 工具概览

| Skill | 职责 | 输入 | 输出 | 外部后端 |
|-------|------|------|------|---------|
| **ppt-extract** | PPT/PDF 双通道内容提取 | `.pptx` / `.pdf`（幻灯片） | 结构化 Markdown + 幻灯片截图 | — |
| **web-pdf-extract** | 网页 PDF 转纯净 Markdown | `.pdf`（网页导出文档） | 纯净 Markdown + 内嵌插图 | — |
| **addToObsidian** | 提取内容融入 Obsidian Vault | ppt-extract / web-pdf-extract 输出 | Obsidian `.md`（含 YAML frontmatter + wiki-links） | — |
| **kg-update** | 增量更新知识图谱 | Obsidian vault `.md` 变更 | graph.json + enriched `.md` | [AI-KG](https://github.com/xqfgbc/my-kg-pipeline) |
| **kg-qa** | 知识图谱问答检索 | 自然语言问题 | 带来源追溯的结构化答案 | [AI-KG](https://github.com/xqfgbc/my-kg-pipeline) |

> **注意**：`kg-update` 和 `kg-qa` 的后端实现（`pipeline.py`、`retrieval.py`、extractors）在 [AI-KG](https://github.com/xqfgbc/my-kg-pipeline) 仓库中。这两个 skill 的 `SKILL.md` 通过绝对路径引用 AI-KG 的脚本。完整部署需单独克隆 AI-KG。

## 数据流

```
PPT/PDF 文件
    │
    ├── ppt-extract ──────────→ 结构化 Markdown + 幻灯片图片
    │
    └── web-pdf-extract ──────→ 纯净 Markdown + 内嵌插图
            │
            ▼
    addToObsidian ────────────→ Obsidian vault .md
    （YAML frontmatter + [[wiki-links]]）
            │
            ▼
    kg-update ────────────────→ 知识图谱增量更新
    （实体 + 标签共现 + 别名发现 + graph.json）
            │
            ▼
    kg-qa ────────────────────→ 问答检索
    （实体匹配 → 原文定位 → 带来源追溯回答）
```

## 安装

```bash
# 1. 克隆本仓库
git clone https://github.com/xqfgbc/kg-tools.git ~/Documents/accenture/AI应用/kg-tools

# 2. 克隆后端依赖（kg-update / kg-qa 需要）
git clone https://github.com/xqfgbc/my-kg-pipeline.git ~/Documents/accenture/AI应用/AI-KG

# 3. 配置本地路径（addToObsidian 需要）
cp ~/Documents/accenture/AI应用/kg-tools/addToObsidian/config.example.sh \
   ~/Documents/accenture/AI应用/kg-tools/addToObsidian/config.sh
# 编辑 config.sh，设置你的 Obsidian vault 路径

# 4. 建立 Claude Code skill 符号链接
ln -sf ~/Documents/accenture/AI应用/kg-tools/ppt-extract ~/.claude/skills/ppt-extract
ln -sf ~/Documents/accenture/AI应用/kg-tools/web-pdf-extract ~/.claude/skills/web-pdf-extract
ln -sf ~/Documents/accenture/AI应用/kg-tools/addToObsidian ~/.claude/skills/addToObsidian
ln -sf ~/Documents/accenture/AI应用/kg-tools/kg-update ~/.claude/skills/kg-update
ln -sf ~/Documents/accenture/AI应用/kg-tools/kg-qa ~/.claude/skills/kg-qa

# 5. 安装 ppt-extract 环境依赖
bash ~/Documents/accenture/AI应用/kg-tools/ppt-extract/setup.sh

# 6. 安装 AI-KG 依赖
pip install -r ~/Documents/accenture/AI应用/AI-KG/requirements.txt
```

## 使用

### ppt-extract — 提取 PPT 内容

```
/ppt-extract /path/to/presentation.pptx
```

输出：与 PPT 同名的文件夹，含结构化 `{name}.md` + `asset/slide_NN.png` 截图。

### web-pdf-extract — 提取网页 PDF

```
/web-pdf-extract /path/to/document.pdf
```

输出：与 PDF 同名的文件夹，含纯净 `{name}.md` + `asset/pageN_imgM.png` 插图。自动剥离网页导航、URL 水印等噪音，生成全文摘要和标签。

### addToObsidian — 融入 Obsidian

```
/addToObsidian {extract_output_dir}
```

自动检测输入类型（ppt-extract 或 web-pdf-extract），构建 YAML frontmatter，注入 `[[wiki-links]]`，复制 `asset/` 到 vault。

### kg-update — 更新知识图谱

```
/kg-update
```

增量检测 vault 变更 → 更新图谱 → 同步 dashboard。无变更时自动退出。

### kg-qa — 检索问答

```
/kg-qa AIOps怎么结合ServiceNow
```

检索知识图谱，返回带来源追溯（Obsidian 深链接）的答案。

## 文档格式兼容性

管道同时支持两种上游提取格式，在实体匹配、关联发现、原文引用、全文搜索全链路表现一致：

| 维度 | ppt-extract | web-pdf-extract |
|------|------------|-----------------|
| **标签格式** | `> 🏷️ 标签:` (per-slide) | `> **Tags**:` (document-level) |
| **内容定位** | `## Slide N` | `##`/`###` 章节标题 + `## 摘要` 回退 |
| **摘要格式** | `> 📝 摘要:` (per-slide, ≤300字) | `> 📝 摘要:` (per-section, ≤300字) + `## 摘要` (全文) |
| **总体摘要** | `📋 总体概要` 表格 (≤300字) | `## 摘要` 段落 (≤300字) |
| **图片命名** | `asset/slide_NN.png` | `asset/pageN_imgM.png` |

## 环境要求

| 工具 | 用途 | 相关 Skill |
|------|------|-----------|
| `pdfplumber` (≥0.10) | PDF 文本提取 | ppt-extract, web-pdf-extract |
| `PyMuPDF` (fitz) | PDF 图片提取 | web-pdf-extract |
| `python-pptx` | PPTX 结构化提取 | ppt-extract |
| `LibreOffice` (≥26.x) | PPTX → PDF 转换 | ppt-extract |
| `pdftoppm` (poppler) | PDF → PNG 转换 | ppt-extract |
| `tesseract` (≥5.x) | OCR 文字识别 | ppt-extract |
| `jieba` | 中文分词 | kg-qa |
| `scikit-learn` | TF-IDF 向量化 | kg-qa |
| `python-frontmatter` | YAML frontmatter 解析 | kg-update |
| `PyYAML` | YAML 配置解析 | kg-update, kg-qa |

## License

MIT
