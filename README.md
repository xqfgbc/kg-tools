# KG Tools — 知识库工具链

AI/IT 运维知识库的完整工具链，覆盖「PPT/PDF 提取 → Obsidian 融入 → 知识图谱构建 → 问答检索」全流程。本仓库为 Claude Code Skill 定义的权威来源。

## 仓库结构

```
kg-tools/
├── README.md
├── .gitignore
├── ppt-extract/               ← PPT/PDF 双通道提取（含实现脚本）
│   ├── SKILL.md
│   ├── batch_extract.sh       # 批量提取：PPTX→PDF→PNG→结构化（幂等、带并发锁）
│   ├── batch_ocr.sh           # 批量 OCR（chi_sim+eng，幂等）
│   ├── AUTHORING_BRIEF.md     # 第六步「编写结构化 Markdown」的完整规范
│   ├── extract_pptx.py        # PPTX 结构化提取
│   ├── extract_pdf.py         # PDF 结构化提取
│   ├── setup.sh               # 环境安装脚本
│   └── config.example.sh      # 配置模板（config.sh 不提交，本地使用）
├── web-pdf-extract/           ← 网页 PDF 转纯净 Markdown
│   └── SKILL.md
├── addToObsidian/             ← 提取内容融入 Obsidian Vault
│   ├── skill.md
│   └── .env.example           # 配置模板（.env 不提交）
├── kg-update/                 ← 知识图谱增量更新
│   ├── SKILL.md
│   └── .env.example
├── kg-qa/                     ← 知识图谱问答检索
│   ├── SKILL.md
│   └── .env.example
└── kb-ingest/                 ← 全链路编排（任意文件夹 → 知识库）
    ├── SKILL.md
    ├── state.py               # 进度清单，支持断点续跑
    ├── verify.py              # 验收断言（入库后）
    ├── audit.py               # 对账：哪些源文件还没进知识库（入库前/巡检）
    ├── .local/                # 运行时状态（kb-ingest-state.json），已 gitignore
    └── .env.example
```

> **哪些进版本管理**：skill 定义、可执行脚本、规范文档进；`config.sh`、`.env`、
> `kb-ingest/.local/`（运行时状态）不进——它们是本机专属的，入库只会让工作区一直脏着。

## 工具概览

| Skill | 职责 | 输入 | 输出 | 外部后端 |
|-------|------|------|------|---------|
| **ppt-extract** | PPT/PDF 双通道内容提取 | `.pptx` / `.pdf`（幻灯片） | 结构化 Markdown + 幻灯片截图 | — |
| **web-pdf-extract** | 网页 PDF 转纯净 Markdown | `.pdf`（网页导出文档） | 纯净 Markdown + 内嵌插图 | — |
| **addToObsidian** | 提取内容融入 Obsidian Vault | ppt-extract / web-pdf-extract 输出 | Obsidian `.md`（含 YAML frontmatter + wiki-links） | — |
| **kg-update** | 增量更新知识图谱 | Obsidian vault `.md` 变更 | graph.json + enriched `.md` | [AI-KG](https://github.com/xqfgbc/my-kg-pipeline) |
| **kg-qa** | 知识图谱问答检索 | 自然语言问题 | 带来源追溯的结构化答案 | [AI-KG](https://github.com/xqfgbc/my-kg-pipeline) |
| **kb-ingest** | 全链路编排 | 任意文件夹的 `.pptx`/`.pdf` | 已入库且验收通过的 Obsidian 文档 | 上面四个 |

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

**`kb-ingest` 把上面这条链串成一条命令**，并带进度清单与验收：

```
/kb-ingest <任意文件夹>        # 提取 → 融入 → 更新图谱 → 验收，可中断续跑
/kb-ingest --sync              # 扫描 .env 里 SOURCE_ROOTS，只处理新增/变更
```

## 安装

```bash
# 1. 克隆本仓库
git clone https://github.com/xqfgbc/kg-tools.git ~/Documents/accenture/AI应用/kg-tools

# 2. 克隆后端依赖（kg-update / kg-qa 需要）
git clone https://github.com/xqfgbc/my-kg-pipeline.git ~/Documents/accenture/AI应用/AI-KG

# 3. 配置本地路径（各 skill 通过 .env 加载，不提交 Git）
KG=~/Documents/accenture/AI应用/kg-tools
for s in addToObsidian kg-update kg-qa kb-ingest; do
  cp "$KG/$s/.env.example" "$KG/$s/.env"
done
cp "$KG/ppt-extract/config.example.sh" "$KG/ppt-extract/config.sh"
# 编辑上述文件，设置本机路径；四个 .env 里的 KG_PYTHON 必须是同一个解释器

# 4. 建立 Claude Code skill 符号链接（单一事实来源，改仓库即生效）
for s in ppt-extract web-pdf-extract addToObsidian kg-update kg-qa kb-ingest; do
  ln -sfn "$KG/$s" ~/.claude/skills/$s
done

# 5. 安装 ppt-extract 环境依赖
bash "$KG/ppt-extract/setup.sh"

# 6. 安装 AI-KG 依赖（必须装进 $KG_PYTHON 指向的那个解释器）
uv pip install --python "$KG_PYTHON" -r ~/Documents/accenture/AI应用/AI-KG/requirements.txt
```

> **⚠️ 用符号链接，不要拷贝。** 拷贝会在两处产生不同版本的 skill，
> 曾经就因此让 `ppt-extract` 的 SKILL.md 在两边出现分叉。

## 使用

### ppt-extract — 提取 PPT 内容

单份（在 Claude Code 里）：

```
/ppt-extract /path/to/presentation.pptx
```

批量（直接调脚本，推荐——幂等可续跑，且内置了防踩坑的校验）：

```bash
bash ppt-extract/batch_extract.sh /path/to/folder    # PPTX→PDF→PNG→结构化提取
bash ppt-extract/batch_ocr.sh     /path/to/folder    # OCR（可选，可后补）
```

随后按 `ppt-extract/AUTHORING_BRIEF.md` 逐份撰写 `{name}.md`。

输出：源文件夹下每份文档一个同名子目录，含结构化 `{name}.md` +
`asset/slide_NN.png` 截图。

> **为什么不把这几步写成 SKILL 里的内联片段**：踩过两个**静默出错**的坑——
> `printf %02d` 把 `slide-08.png` 的前导 0 当八进制，导致第 8、9 页图片互相覆盖丢失
> 而脚本不报错；手抄含 U+00A0 不换行空格的文件名会整份漏掉。脚本里已修并加了自检。

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

### kb-ingest — 一条命令走完全链路

```
/kb-ingest /path/to/folder        # 文件或文件夹，任意位置
/kb-ingest --sync                 # 扫描 SOURCE_ROOTS，只处理新增/变更
```

提取 → 融入 Obsidian → 更新图谱 → 验收，全自动。带进度清单
（`$KB_STATE_DIR/kb-ingest-state.json`），中断后可续跑，源文件没变就跳过。

> **检索机制的边界**：`kg-qa` 的实体匹配是 TF-IDF（字符 n-gram）+ 余弦相似度，
> **不是语义嵌入**。它衡量字符重叠而非语义相近，问法与实体名用词不重叠时可能漏召回。
> 别名表（`config.aliases.local.yaml`）就是在人工补偿这个缺口。

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
