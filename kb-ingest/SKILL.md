---
name: kb-ingest
description: |
  把任意文件夹里的 PPT/PDF 文档批量灌入知识库的编排器：
  ppt-extract 提取 → addToObsidian 融入 Obsidian → kg-update 更新图谱 → 验收。
  带进度清单，支持断点续跑与增量同步（源文件没变就跳过），
  以后新增的文件夹只要登记或直接传路径即可。
tags: [knowledge-graph, ingest, pipeline, orchestration, obsidian]
---

# 知识库入库编排 (KB-Ingest)

一条命令把**任意文件夹**里的 PPT/PDF 送进知识库，并验收结果。

本 skill **只做编排与状态管理**，不复制实现：提取逻辑在 `ppt-extract`，
Obsidian 规范在 `addToObsidian`，图谱在 `kg-update` / AI-KG，问答在 `kg-qa`。

## 数据流

```
源文件夹（任意位置）
    │
    ├─ ① ppt-extract ──→ {源目录}/{name}/{name}.md + asset/
    │                     逐份进行，产物落在源文件旁边
    │
    ├─ ② addToObsidian ─→ $VAULT_PATH/{标题}/{标题}.md
    │                     逐份进行，加 frontmatter + 关联章节
    │
    ├─ ③ kg-update ─────→ graph.json
    │                     全部文档做完后只跑一次
    │
    └─ ④ verify ────────→ 断言图谱覆盖完整、产物可用
```

> **为什么要「全部做完再跑一次 kg-update」**：管道每轮都会整体导出 `graph.json`，
> 逐份触发等于每份都重建一次全图，纯属浪费。批量做一次即可。

## 配置

路径与解释器通过 `.env` 配置（本地文件，不提交 Git）：

```bash
cp .env.example .env    # 首次使用，然后按本机情况编辑
```

```bash
KG_TOOLS_DIR=/path/to/kg-tools          # 四个子 skill 所在处
KG_PROJECT_DIR=/path/to/AI-KG           # kg-update / kg-qa 后端
VAULT_PATH=/path/to/obsidian/vault
KG_PYTHON=/path/to/venv/bin/python3     # 全链路统一解释器
KB_STATE_DIR=/path/to/state             # 进度清单目录（留空则用本 skill 的 .local/）
SOURCE_ROOTS=/path/a:/path/b            # 长期同步的源文件夹，冒号分隔
```

> **`KB_STATE_DIR` 是运行时状态，不入版本管理**（`.local/` 已 gitignore）。
> 每跑一次入库它都会被改写，且只对本机有意义——放进仓库只会让工作区一直脏着。
> 也不要把它放在 `SOURCE_ROOTS` 里，否则清单自己会被当成待处理内容。

> **⚠️ 必须用 `$KG_PYTHON`**，不要用裸 `python3`（缺 jieba / scikit-learn / networkx /
> python-frontmatter，会直接 ImportError）。本机可用：
> `/Users/bo.gong/.venvs/ai-kg/bin/python3`。

## 用法

```
/kb-ingest <路径>…            # 文件或文件夹，任意位置
/kb-ingest --sync             # 扫描 $SOURCE_ROOTS，处理新增/变更的
/kb-ingest --stage <阶段> <路径>   # 只跑某一段：extract | obsidian | kg | verify
/kb-ingest --force <路径>     # 忽略进度清单，重新处理
```

`--stage` 用于排查单段问题（比如只重跑融入 Obsidian 而不重新提取）。

## 对账：哪些文件还没进知识库

```bash
"$KG_PYTHON" "$KG_TOOLS_DIR/kb-ingest/audit.py" --graph
```

把「源目录里有什么」和「知识库里有什么」对起来，逐份给出状态；退出码 1 表示存在缺口。

| 状态 | 含义 | 处理 |
|---|---|---|
| ✅ 已入库 | 三层齐备：源文件在、清单记 `ingested`、vault 里有 `.md`（`--graph` 时还在图谱里） | — |
| ⏳ 待入库 | 已提取已撰写，但没进 vault | 跑 Step 3 |
| ⏳ 提取中 | 有 `asset/` 但还没写完 | 继续 Step 2 |
| ❌ 未处理 | 源文件在，从未处理 | 跑 Step 2 |
| 🚫 无法处理 | DRM/IRM 加密（OLE2 且无 `PowerPoint document` 流） | 需在 PowerPoint 中导出未加密副本 |
| ⚠️ 异常 | 清单说已入库但 vault 里没有；或 vault 有但不在图谱里 | 分别排查，后者跑 `/kg-update` |

它还会列出**反向情况**：vault 里有、但不对应任何已登记源文件的文档（早期手工放入的正常如此），
以及源目录里管线不处理的格式（`.docx`、`.txt` 等），后者只是提示、不算失败。

> **对账能抓出的典型问题**（都实际发生过）：
> - **同一份文档的两种格式**（如 `X.pptx` 与 `X.pdf`）—— 两份都会被当成独立文档入库，产生重复。入库前先确认保留哪一份。
> - **单页碎片**：几十 KB、只有 0–1 页、内容是别的主题的 pptx，通常是误导出，不是文档。
> - **清单记错了源**：同一份文档既有加密 `.pptx` 又有导出 `.pdf` 时，容易把记录挂到不能处理的那个上。

## 工作流程

所有步骤先装载配置：

```bash
source "{skill_dir}/.env"
STATE="$KG_TOOLS_DIR/kb-ingest/state.py"
```

### Step 1: 摸清待办

```bash
"$KG_PYTHON" "$STATE" scan <路径>…      # 或 "$SOURCE_ROOTS"（--sync 时）
```

输出每份文档的 `status`：

| status | 含义 | 该做什么 |
|--------|------|---------|
| `todo` | 从未处理 | 从提取开始 |
| `resume` | 提取过了，还没入库 | 从融入 Obsidian 继续（`stage=extracted`）|
| `done` | 已入库 | 跳过 |
| `source-changed` | 源文件变了 | 从提取重新开始 |

**把「待处理 / 已跳过」清单打印给用户看再开工。**

### Step 2: 逐份提取（ppt-extract）

**调脚本，不要手写循环**（手抄文件名会因 U+00A0 之类的不可见字符静默漏文档；
内联 `printf` 重命名会因八进制问题静默丢页——两个坑都真实发生过）：

```bash
bash "$KG_TOOLS_DIR/ppt-extract/batch_extract.sh" <源目录…>   # 结构产物
bash "$KG_TOOLS_DIR/ppt-extract/batch_ocr.sh"     <源目录…>   # OCR（可选，可后补）
```

产出 `{源目录}/{name}/` 下的 `{name}.pdf`、`extraction_raw.txt`、`asset/slide_NN.png`。
两个脚本都幂等，中断后可续跑。

**然后逐份撰写 `{name}.md`** —— 这是独立且最耗时的一步，
规范见 `$KG_TOOLS_DIR/ppt-extract/AUTHORING_BRIEF.md`。
撰写可以并行推进（每份文档互不依赖）。

每份完成后更新清单：

```bash
"$KG_PYTHON" "$STATE" mark "<源文件绝对路径>" extracted
```

> **大 PPT 单份耗时可观**（20MB / 100+ 页可能几十分钟）。逐份推进，
> 每份结束打印一行进度。中途停下也没关系 —— 已完成的靠清单跳过。

### Step 3: 逐份融入 Obsidian（addToObsidian）

对每份 `status=resume` 的文档，按 `addToObsidian/skill.md` 处理：
构建 frontmatter（**含 `title`**）、复制 `asset/`、插入 `## 🔗 关联文档`。

```bash
"$KG_PYTHON" "$STATE" mark "<源文件绝对路径>" ingested \
  --vault-path "<vault相对路径，如 'XXX/XXX.md'>"
```

### Step 4: 更新图谱（kg-update，只跑一次）

**Step 2/3 全部做完之后**再执行：

```bash
"$KG_PYTHON" "$KG_PROJECT_DIR/kg-pipeline/pipeline.py"
```

管道是增量的：只有变更文件会被解析与回写，未变更文件复用缓存，
但图谱始终由全部文档重建，所以不会丢文档。

### Step 5: 验收

```bash
"$KG_PYTHON" "$KG_TOOLS_DIR/kb-ingest/verify.py" \
  --doc "<新文档的 vault 相对路径>"   # 每份新文档一次
```

`verify.py` 检查：

1. `graph.json` 的 document 节点数 == vault 内 `.md` 数（**图谱没被截断**）
2. 指定文档确实在 `graph.json` 的 document 节点里
3. 该文档 frontmatter 能解析、有 `title`、有 `tags`
4. **标签里没有禁用词** —— 撰写时过滤掉了还不够：**管道会在回写 frontmatter 时从正文重新派生标签**，把「封面/目录/附录」这类词和公司名加回来。管道侧的 `exclude_tags` 是兜底（见 `kg-update`），这一条是验收
5. 关联章节恰好 **1 个**（不是 0 也不是 2）
6. 所有 `![](asset/...)` 引用的文件都存在

任一项失败就**如实报告，不要跳过**。退出码非 0 时先修问题再继续。

### Step 6: 端到端抽查

挑一份新入库的文档，用 `/kg-qa` 提一个只有该文档才答得出的问题，
确认答案里带 `obsidian://open?vault=…` 深链接。这是「真的能被检索到」的最终证据。

## 增量同步：以后新增的文件夹怎么办

**方式一（临时）**：直接传路径，不登记

```
/kb-ingest /任意/新文件夹
```

**方式二（长期）**：把文件夹写进 `.env` 的 `SOURCE_ROOTS`（冒号分隔），之后

```
/kb-ingest --sync
```

只处理新增或改动的文件，已入库的直接跳过。

> 源文件夹在 vault 之外，管道完全看不见它们 —— 只有被复制进 vault 的 `.md`
> 才进入知识库。所以文档来自哪个文件夹，不影响它进的是哪张图：全局只有一张图谱。

## 进度清单

`$KB_STATE_DIR/kb-ingest-state.json` —— **默认 `kb-ingest/.local/`，已 gitignore**。
这是运行时状态而非源码：每次入库都会改写，且只对本机有意义，所以不入版本管理。

按源文件绝对路径记录：

```jsonc
"/path/to/deck.pptx": {
  "source_hash": "…",          // 源文件 MD5，变了就重做
  "stage": "ingested",         // extracted | ingested
  "vault_path": "XXX/XXX.md",
  "updated_at": "2026-10-15T13:40:00+00:00"
}
```

查看与重置：

```bash
"$KG_PYTHON" "$STATE" status
"$KG_PYTHON" "$STATE" reset "<源文件路径>"
```

## 注意事项

- **`KB_STATE_DIR` 已 gitignore**（默认 `kb-ingest/.local/`）：它是运行时状态，
  不要提交进仓库，也不要放在 `SOURCE_ROOTS` 里（否则清单自己会被当成待处理内容）
- 提取产物（`{name}.pdf`、`slide_*.png`）留在源文件夹旁边，这是 `ppt-extract` 的既定约定；
  它们不会被当成新的输入文档（只认 `.pptx` / `.pdf`）
- 若源文件夹里已有提取产物，`state.py scan` 不会把中间 PDF 误判为新输入 —— 但**同一个文件夹
  里不要同时放原始 PDF 和它的 PPTX**，否则会被当成两份不同的文档
- 首次启用图谱提取缓存时，`kg-update` 会解析全部文档一次（之后才是纯增量），属正常现象
- 验收失败时优先跑 `/kg-update`，它能修掉绝大多数「文档没进图谱」的问题
