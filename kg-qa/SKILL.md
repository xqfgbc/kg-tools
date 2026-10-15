---
name: kg-qa
description: |
  基于 AI/IT 运维知识图谱的问答。通过检索知识图谱中的实体、关联关系和原文摘要，
  结合大模型来回答用户问题。每个答案都附带来源追溯（文档名+幻灯片编号）。
tags: [knowledge-graph, qa, rag,运维, aiops]
---

# 知识库问答 (KG-QA)

当用户提出 AI/IT 运维领域的问题时，从知识图谱中检索相关知识，结合原文内容给出带来源追溯的回答。

## 项目路径配置

AI-KG 项目路径、Vault 路径和 Python 解释器通过 `.env` 文件配置（本地文件，不提交 Git）：

```bash
# 首次使用：复制配置模板
cp .env.example .env
# 编辑 .env，设置你的路径
```

```bash
# .env 内容
KG_PROJECT_DIR=/path/to/AI-KG
VAULT_PATH=/path/to/obsidian/vault
KG_PYTHON=/path/to/venv/bin/python3
```

> **⚠️ 必须用 `$KG_PYTHON`，不要用裸 `python3`。**
> 检索依赖 `jieba`、`scikit-learn`、`PyYAML`。系统自带的 `/usr/bin/python3` 一个都没有。
> （旧版本文档里写的 conda 路径 `/opt/miniconda3/bin/python` 在本机已不存在，不要再引用。）
> 本机可用环境：`/Users/bo.gong/.venvs/ai-kg/bin/python3`。

## 工作流程

### Step 0: 图谱新鲜度自检

先确认图谱覆盖了 vault 里的全部文档再检索，否则答案会凭空缺失某些文档：

```bash
source "{skill_dir}/.env"
"$KG_PYTHON" - <<'PY'
import json, os
kg, vault = os.environ["KG_PROJECT_DIR"], os.environ["VAULT_PATH"]
g = json.load(open(os.path.join(kg, "kg-pipeline-data/graph.json")))
docs = {n["id"] for n in g["nodes"] if n["type"] == "document"}
md = [f for r, _, fs in os.walk(vault) for f in fs
      if f.endswith(".md") and ".obsidian" not in r and "/asset/" not in r]
print(f"图谱文档数: {len(docs)}   vault 文档数: {len(md)}")
if len(docs) != len(md):
    print("⚠️  不一致 —— 图谱可能被截断，请先运行 /kg-update 再提问")
PY
```

不一致时**先跑 `/kg-update`**，不要基于残缺的图谱作答。

### Step 1: 检索

```bash
source "{skill_dir}/.env"
cd "$KG_PROJECT_DIR" && "$KG_PYTHON" kg-pipeline/retrieval.py "<用户问题>"
```

返回的 JSON 包含：
- `matched_entities` — 匹配到的实体及来源文档数
- `related_concepts` — 共现关联最强的概念（按权重排序）
- `source_passages` — 原文幻灯片摘要，含文档名、幻灯片编号、标题、摘要
- `fulltext_matches` — 全文搜索到的补充段落

> **检索机制说明**：实体匹配用的是 TF-IDF（字符 2–4 gram）+ 余弦相似度，**不是语义嵌入**。
> 它衡量字符重叠而非语义相近，所以问法与实体名用词不重叠时可能漏召回。
> 检索结果为空或明显偏少时，换用**实体表里实际出现的词**（英文术语、缩写）重试，
> 或先在图谱中查一下相关实体名再问。

### Step 2: 组织上下文

从检索结果中提取：

1. **核心实体** — `matched_entities` 前 5 个
2. **关联概念** — `related_concepts` 前 10 个，说明概念间的关联关系
3. **原文证据** — `source_passages` 中的摘要，这是可直接引用的原文内容
4. **补充信息** — `fulltext_matches` 作参考

### Step 3: 回答问题

- **必须引用来源**：每条关键信息标注 Obsidian 可点击链接，格式为：
  ```
  【来源：[文档名 > 幻灯片编号](obsidian://open?vault=AI&file=<url编码路径>#<url编码标题>)】
  ```
- **构建 Obsidian 链接**：从 `source_passages` 中取 `doc` 和 `slide` 字段，按如下规则拼接：
  - vault 固定为 `AI`
  - `file` = `doc` 字段的 URL 编码值（空格→`%20`、`&`→`%26`）
  - fragment（`#` 之后）= slide 标题的 URL 编码值（如 `Slide%205`）
  - 示例：`obsidian://open?vault=AI&file=Enterprise%20Observability%20%26%20AIOps%2Fobservability-aiops%20strategy%20stage%200.md#Slide%205`
- **URL 编码对照**：
  | 字符 | 编码 | 说明 |
  |------|------|------|
  | 空格 | `%20` | |
  | `&` | `%26` | **必须编码**，否则破坏 query string |
  | `/` | `%2F` | 路径分隔符 |
  | `#` | `%23` | 仅 file 参数中需要 |
- **优先原文摘要**：`source_passages` 中的内容是 PPT 原文，直接引用
- **图谱关联做补充**：`related_concepts` 反映统计共现，可提示用户探索相关概念
- **知识库无法回答时**：诚实告知，说明知识库当前覆盖范围有限
- **结构化呈现**：实现步骤、效果指标等使用表格或列表

### Step 4（可选）: 补充原文细节

如果 `source_passages` 中的摘要不够详细，可以直接读取对应 .md 文件中具体幻灯片的完整内容：

```bash
grep -A 50 "^## Slide N" "$VAULT_PATH/<文档路径>"
```

## 知识库范围

**不要硬编码文档清单** —— vault 内容会持续增长，写死的列表很快就会过期。
需要说明覆盖范围时，用 Step 0 的自检命令或直接列目录取得实际文档：

```bash
ls "$VAULT_PATH"
```

## 注意事项

- 检索脚本路径是绝对路径，确保在任意目录下都能执行
- **必须用 `$KG_PYTHON`**（见上方警告），不要用裸 `python3` 或文档历史版本里的 conda 路径
- 如果检索结果为空，尝试用英文关键词、缩写或实体表中实际出现的同义词重新检索
- 图谱中实体间 `cooccurs_with` 权重仅反映标签共现频率，不代表因果关系
- 只有一个知识图谱（`kg-pipeline-data/graph.json`）。管道只扫 vault 一个根目录，
  文档来自哪个源文件夹不影响它进入哪张图 —— 只要是已入库的文档，就在同一张图里。
