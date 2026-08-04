# addToObsidian — 提取内容融入 Obsidian Vault

## 概述

将 **ppt-extract** 或 **web-pdf-extract** 技能产出的结构化 Markdown 文档及资产图片，融入已有的 Obsidian vault，使其具备 YAML 标签、双向链接、图谱视图等 Obsidian 原生能力。

## 默认 Vault 路径

```
/Users/bo.gong/Documents/accenture/obsidian/AI/
```

> 该路径与 `kg-qa`、`kg-update` 两个 skill 共用同一个 vault，形成「PPT提取 → Obsidian融入 → 知识图谱更新 → 问答检索」的完整工具链。

---

## 输入类型自动检测

本 skill 同时支持两种上游 skill 的输出。在开始处理前，先检测输入来源：

```bash
SOURCE_MD="{extract_output_dir}/{name}.md"

# 检测输入类型
if grep -q "^## Slide" "$SOURCE_MD"; then
  INPUT_TYPE="ppt-extract"
elif grep -q "^> \*\*Tags\*\*:" "$SOURCE_MD"; then
  INPUT_TYPE="web-pdf-extract"
else
  echo "❌ 无法识别的输入格式"
  exit 1
fi
echo "📋 输入类型: $INPUT_TYPE"
```

| 特征 | ppt-extract | web-pdf-extract |
|------|------------|-----------------|
| 章节标题 | `## Slide N: {标题}` | `## {章节标题}` / `### {小节}` |
| 摘要位置 | `## 📋 总体概要`（表格） | `## 摘要`（段落） |
| 标签位置 | 总体概要表格 + 每页 `🏷️ 标签:` | `> **Tags**:`（blockquote 行内 `` `tag` ``） |
| 图片命名 | `asset/slide_NN.png` | `asset/pageN_imgM.png` |
| 页数/章节 | 幻灯片总数 = `^## Slide` 行数 | 章节/小节总数 = `^## ` 行数 + `^### ` 行数 |

---

## 前置条件

| 条件 | 检查方式 |
|------|----------|
| **Obsidian Vault 已存在** | 默认路径 `/Users/bo.gong/Documents/accenture/obsidian/AI/` 存在且包含 `.md` 文件 |
| **内容已提取完成** | 存在 ppt-extract 或 web-pdf-extract 输出目录，包含 `<name>.md` + `asset/*` |
| **Vault 中有可参考的现有文档** | 查看现有 `.md` 文件的 frontmatter 格式和标签风格 |
| **资产图片可访问** | `asset/` 目录中有对应图片文件 |

---

## 工作流程

### 第一步：检查 Vault 结构与参考格式

```bash
# 查看 vault 目录结构
ls "{vault_path}/"

# 查看现有文档的 frontmatter 格式
head -30 "{vault_path}"/*/*.md
```

从现有文档中提取：
- 标签命名风格（中文/英文、层级粒度）
- 自定义 frontmatter 字段（如 `document-type`、`version`、`created`）
- 文档命名规范

### 第二步：确定文档命名

> **核心规则**：文件夹名 = .md 文件名 = 可读标题。命名规则因上游 skill 而异。

**ppt-extract 命名转换规则**：

| 步骤 | 操作 | 示例 |
|------|------|------|
| 1. 取源文件名 | 去掉 `.pdf`/`.pptx` 扩展名 | `Artificial Intelligence architecture framework & principles_v2.0` |
| 2. 去版本号 | 移除 `_v2.0`、`v1` 等版本后缀 | `Artificial Intelligence architecture framework & principles` |
| 3. 规范化 | 下划线 `_` → 空格，`&` 保留 | `Artificial Intelligence architecture framework & principles` |
| 4. 转标题大小写 | 每个单词首字母大写（介词/连词除外） | `AI Architecture Framework & Principles` |

**web-pdf-extract 命名转换规则**：

| 步骤 | 操作 | 示例 |
|------|------|------|
| 1. 取源文件名 | 去掉 `.pdf` 扩展名 | `Ontology design_ Best practices • Palantir` |
| 2. 去特殊字符 | `•` `—` `–` 替换为 `-`；`_` 替换为空格 | `Ontology design - Best practices - Palantir` |
| 3. 提取主标题 | 取 `:` 或 `-` 之前的主要部分 | `Ontology design - Best practices` |
| 4. 转标题大小写 | 每个单词首字母大写（介词/连词除外） | `Ontology Design - Best Practices` |

```bash
FOLDER_NAME="{生成的标题}"
TARGET_DIR="{vault_path}/${FOLDER_NAME}"
mkdir -p "${TARGET_DIR}/asset"
```

> **注意**：文件夹和 .md 文件使用相同名称。图片统一放在 `asset/` 子目录下。

### 第三步：复制资产文件

两种输入类型的图片路径统一为 `asset/`：

```bash
# 复制图片到 vault
cp "{extract_output_dir}/asset/"* "${TARGET_DIR}/asset/"
```

> **注意**：Markdown 中的图片引用路径为 `asset/...`（相对路径），复制后路径保持不变。无论图片命名是 `slide_NN.png` 还是 `pageN_imgM.png`，引用均正常工作。

### 第四步：提取元信息

根据输入类型，从源文件中提取摘要和标签。

#### 4a. ppt-extract 输入

```bash
# 提取总体摘要（📋 总体概要 表格中的"摘要"行）
SUMMARY=$(sed -n '/📋 总体概要/,/^## /p' "$SOURCE_MD" | grep '摘要' | head -1)

# 提取总体标签（📋 总体概要 表格中的"标签"行）
GLOBAL_TAGS=$(sed -n '/📋 总体概要/,/^## /p' "$SOURCE_MD" | grep '标签' | head -1)

# 提取各幻灯片标签（🏷️ 标签: 行）
SLIDE_TAGS=$(grep '^> \*\*🏷️ 标签:\*\*' "$SOURCE_MD" | sed 's/> \*\*🏷️ 标签:\*\* //')

# 页码 = 幻灯片数量
PAGE_COUNT=$(grep -c '^## Slide' "$SOURCE_MD")
```

标签汇总：从 `GLOBAL_TAGS` 和 `SLIDE_TAGS` 中提取所有 `` `tag` ``，去重后取高频标签（20-30 个）。

#### 4b. web-pdf-extract 输入

```bash
# 提取摘要（## 摘要 章节，到下一个 --- 或 ## 为止）
SUMMARY=$(sed -n '/^## 摘要$/,/^---$/p' "$SOURCE_MD" | grep -vE '^(## |---$)' | sed '/^$/d')

# 提取标签（> **Tags**: 行中的行内标签，与 inline_tag_extractor 的 ENGLISH_TAG_PATTERN 对齐）
TAGS_LINE=$(grep '^> \*\*Tags\*\*:' "$SOURCE_MD" | head -1)

# 章节数 = H2 + H3 标题数（排除 ## 摘要 等元信息标题）
SECTION_COUNT=$(grep -cE '^## (摘要|🔗|幻灯片)' "$SOURCE_MD" || echo 0)
CONTENT_H2=$(grep -c '^## ' "$SOURCE_MD")
CONTENT_H3=$(grep -c '^### ' "$SOURCE_MD")
PAGE_COUNT=$((CONTENT_H2 + CONTENT_H3 - SECTION_COUNT))
```

标签汇总：从 `TAGS_LINE` 中解析所有 `` `tag` ``，直接作为标签列表（10-20 个）。

### 第五步：构建 YAML Frontmatter

根据提取的元信息和输入类型，生成 Obsidian YAML frontmatter：

```yaml
---
tags:
  - {tag1}
  - {tag2}
  - ...
aliases:
  - "{英文全称}"
  - "{缩写}"
  - "{中文简称}"
created: {YYYY-MM-DD}
document-type: "{ppt-extract: ETB/案例/白皮书 等 | web-pdf-extract: 文档/指南/白皮书}"
source: "{ppt-extract: PPT文件名 | web-pdf-extract: PDF原始URL或文件名}"
{pages: N}           ← ppt-extract 保留，web-pdf-extract 改为 sections: N
---
```

| 字段 | ppt-extract | web-pdf-extract |
|------|------------|-----------------|
| `tags` | 从总体标签 + 幻灯片标签汇总去重（20-30 个） | 从 `> **Tags**:` 行解析（10-20 个） |
| `aliases` | 缩写、中英文替代名、版本号 | 原标题（含特殊字符的原始文件名） |
| `created` | PPT 文档日期 | PDF 下载/创建日期 |
| `document-type` | ETB / 案例 / 路线图 等 | 文档 / 指南 / 白皮书 等 |
| `pages` | ✅ 幻灯片页数 | ❌ 改用 `sections`（章节数） |
| `source` | ✅ 源 PPT 文件名 | ✅ 源 PDF 文件名或 URL |

### 第六步：插入 Wiki-Link 关联

**两种输入类型通用**。根据标签重叠度和主题相关性，在元信息区域之后、正文之前插入关联文档区块。

**插入位置**：

| 输入类型 | 插入位置 |
|---------|---------|
| ppt-extract | `📋 总体概要` 表格之后、`## 幻灯片目录` 之前 |
| web-pdf-extract | `> **Tags**:` 行之后、`---` 分隔线之前 |

```markdown
## 🔗 相关文档

| 文档 | 关系 |
|------|------|
| [[文档名1]] | 关联关系描述 |
| [[文档名2]] | 关联关系描述 |
```

**关联判断依据**（两种输入通用）：
- **标签重叠度**：输入文档的标签与现有 vault 文档 frontmatter `tags` 交集越多，关联越强
- **主题相关性**：AI 架构框架 ↔ AI 转型路线图、知识图谱 ↔ 本体设计等
- **技术栈重叠**：共同技术关键词（如 AgenticAI、RAG、Ontology 等）

### 第七步：组装并写入 Obsidian 文档

**文档组装顺序**：

```
---
[YAML Frontmatter]
---

[原始 Markdown 标题和元信息区域]
  - # 标题
  - 来源/摘要/标签 区域

## 🔗 相关文档     ← 插入
| 文档 | 关系 |
|------|------|

[原始 Markdown 正文]
  - ppt-extract: 幻灯片目录 + Slide 1...N + 附录
  - web-pdf-extract: 各章节正文
```

**实现方式**：

```bash
# 1. 先写入 frontmatter
cat > "{target_md}" << 'YAML_EOF'
---
tags: [...]
aliases: [...]
created: ...
document-type: ...
...
---
YAML_EOF

# 2. 去除源文件中的重复元信息标题后追加正文
#    ppt-extract: 跳过第一行标题（已包含在 frontmatter 概念中）
#    web-pdf-extract: 保留 ## 摘要 和 `> **Tags**:` 之前的头部（标题 + 来源），其余直接追加
if [ "$INPUT_TYPE" = "ppt-extract" ]; then
  tail -n +2 "$SOURCE_MD" >> "{target_md}"
elif [ "$INPUT_TYPE" = "web-pdf-extract" ]; then
  # 跳过 # 标题行和 > 来源行（已在 frontmatter 中体现），从 ## 摘要 开始
  sed -n '/^## 摘要/,$ p' "$SOURCE_MD" >> "{target_md}"
fi

# 3. 用 Edit 工具在元信息区域后插入关联文档区块
```

### 第八步：验证

```bash
echo "=== 文件 ===" && ls -lh "{target_md}"
echo "=== 资产 ===" && ls "{target_dir}/asset/" | wc -l
echo "=== Frontmatter ===" && head -20 "{target_md}"

if [ "$INPUT_TYPE" = "ppt-extract" ]; then
  echo "=== 幻灯片数 ===" && grep -c "^## Slide" "{target_md}"
  echo "=== 图片引用 ===" && grep -c "!\[Slide" "{target_md}"
elif [ "$INPUT_TYPE" = "web-pdf-extract" ]; then
  echo "=== 章节数 ===" && grep -cE "^## |^### " "{target_md}"
  echo "=== 图片引用 ===" && grep -c "!\[" "{target_md}"
fi

echo "=== 关联链接 ===" && grep "\[\[" "{target_md}"
```

---

## 输出质量标准

### 通用标准（两种输入类型均需满足）

- [ ] YAML frontmatter 格式正确，在 Obsidian 中可被识别
- [ ] 标签与 vault 现有文档标签风格一致
- [ ] 别名覆盖英文全称、缩写、中文简称
- [ ] 至少关联 2 个 vault 现有文档（通过 `[[wiki-link]]`）
- [ ] 图片引用路径正确（`asset/...`）
- [ ] 正文内容完整，无截断
- [ ] `asset/` 文件夹已复制到 vault 目录下

### ppt-extract 特有

- [ ] 标签数量 20–30 个
- [ ] 幻灯片数量与源文件一致（`grep -c "^## Slide"`）
- [ ] 所有 `![Slide N](asset/slide_NN.png)` 引用有效

### web-pdf-extract 特有

- [ ] 标签数量 10–20 个
- [ ] `frontmatter` 使用 `sections` 字段而非 `pages`
- [ ] 章节引用图片路径正确（`asset/pageN_imgM.png`）
- [ ] 非正文元信息标题（`## 摘要`、`> **Tags**:`）不计入章节数

---

## 常见问题

| 问题 | 规避方式 |
|------|----------|
| **图片不显示** | 必须复制 `asset/` 文件夹到 vault 同目录下，保持相对路径 |
| **标签不生效** | YAML `tags` 字段格式必须是 YAML list（每行 `  - tag`）或 JSON array（`[tag1, tag2]`） |
| **Wiki-Link 失效** | `[[文档名]]` 必须与 vault 中目标 `.md` 文件名（不含路径和扩展名）完全一致 |
| **Frontmatter 解析失败** | `---` 分隔符前后不能有空格，YAML 缩进必须用空格不能用 Tab |
| **文件过大导致性能问题** | 66 页/168KB 在 Obsidian 中可正常处理；若章节更多可考虑拆分为多个 `.md` |
| **输入类型检测失败** | 确保源 `.md` 来自 ppt-extract 或 web-pdf-extract；手动检查 `grep "^## Slide"` 和 `grep "^> \\*\\*Tags\\*\\*: "` |
| **web-pdf-extract 标签格式不兼容** | 行内 `` `tag1` `tag2` `` 格式需解析为 YAML list；注意反引号内的标签可能含空格 |
