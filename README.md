# KG Tools — 知识库工具链

AI/IT 运维知识库的完整工具链，覆盖「PPT/PDF 提取 → Obsidian 融入 → 知识图谱构建 → 问答检索」全流程。

## 工具概览

| Skill | 职责 | 输入 | 输出 |
|-------|------|------|------|
| **ppt-extract** | PPT/PDF 双通道内容提取 | `.pptx` / `.pdf`（幻灯片） | 结构化 Markdown + 幻灯片截图 |
| **web-pdf-extract** | 网页 PDF 转纯净 Markdown | `.pdf`（网页导出文档） | 纯净 Markdown + 内嵌插图 |
| **addToObsidian** | 提取内容融入 Obsidian Vault | ppt-extract / web-pdf-extract 输出 | Obsidian `.md`（含 YAML frontmatter + wiki-links） |
| **kg-update** | 增量更新知识图谱 | Obsidian vault `.md` 变更 | 知识图谱 JSON + enriched `.md` |
| **kg-qa** | 知识图谱问答检索 | 自然语言问题 | 带来源追溯的结构化答案 |

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
# 克隆仓库
git clone <repo-url> ~/Documents/accenture/AI应用/kg-tools

# 建立 Claude Code skill 符号链接
ln -s ~/Documents/accenture/AI应用/kg-tools/ppt-extract ~/.claude/skills/ppt-extract
ln -s ~/Documents/accenture/AI应用/kg-tools/web-pdf-extract ~/.claude/skills/web-pdf-extract
ln -s ~/Documents/accenture/AI应用/kg-tools/addToObsidian ~/.claude/skills/addToObsidian
ln -s ~/Documents/accenture/AI应用/kg-tools/kg-update ~/.claude/skills/kg-update
ln -s ~/Documents/accenture/AI应用/kg-tools/kg-qa ~/.claude/skills/kg-qa
```

## 依赖

| Skill | 外部依赖 | 说明 |
|-------|---------|------|
| ppt-extract | [ppt-extract](https://github.com/...) | 完整项目，含提取脚本（`extract_pptx.py`、`extract_pdf.py`） |
| kg-qa / kg-update | [AI-KG](https://github.com/...) | 知识图谱管道（`pipeline.py`、`retrieval.py`、extractors） |
| addToObsidian | 无 | 纯 Skill 定义，无外部脚本依赖 |
| web-pdf-extract | 无 | 纯 Skill 定义，无外部脚本依赖 |

> **注意**：`ppt-extract` 和 `kg-qa`/`kg-update` 的完整实现代码在各自独立仓库中。本仓库仅包含 Claude Code Skill 定义文件（`SKILL.md`）。完整部署需单独克隆对应仓库。

## 环境要求

| 工具 | 用途 | 相关 Skill |
|------|------|-----------|
| `pdfplumber` | PDF 文本提取 | ppt-extract, web-pdf-extract |
| `PyMuPDF` (fitz) | PDF 图片提取 | web-pdf-extract |
| `python-pptx` | PPTX 结构化提取 | ppt-extract |
| `LibreOffice` | PPTX → PDF 转换 | ppt-extract |
| `pdftoppm` (poppler) | PDF → PNG 转换 | ppt-extract |
| `tesseract` | OCR 文字识别 | ppt-extract |
| `jieba` | 中文分词 | kg-qa |
| `scikit-learn` | TF-IDF 向量化 | kg-qa |
| `python-frontmatter` | YAML frontmatter 解析 | kg-update, addToObsidian |

## 文档格式兼容性

知识图谱管道同时支持两种上游提取格式：

| 来源 | 标签格式 | 内容定位 | 摘要格式 |
|------|---------|---------|---------|
| ppt-extract | `> 🏷️ 标签:` (per-slide) | `## Slide N` | `> 📝 摘要:` (per-slide) |
| web-pdf-extract | `> **Tags**:` (document-level) | `##`/`###` 章节标题 + `## 摘要` 回退 | `> 📝 摘要:` (per-section) + `## 摘要` (全文) |

两种格式在实体匹配、关联发现、原文引用、全文搜索全链路表现一致。

## License

MIT
