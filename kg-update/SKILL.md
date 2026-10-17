---
name: kg-update
description: |
  检查 AI/IT 运维知识库是否有新增或变更的文档，如有变更则增量更新知识图谱。
  更新后自动同步 dashboard 可视化数据。
tags: [knowledge-graph, sync, pipeline,运维]
---

# 知识图谱更新 (KG-Update)

检查 Obsidian 知识库 vault 中的 .md 文件变更，发现新增或修改后增量更新知识图谱。

## 项目路径配置

AI-KG 项目路径与 Python 解释器通过 `.env` 文件配置（本地文件，不提交 Git）：

```bash
# 首次使用：复制配置模板
cp .env.example .env
# 编辑 .env，设置你的路径
```

```bash
# .env 内容
KG_PROJECT_DIR=/path/to/AI-KG
KG_PYTHON=/path/to/venv/bin/python3
```

Skill 执行时通过 `source "{skill_dir}/.env"` 加载这两个变量。

> **⚠️ 必须用 `$KG_PYTHON`，不要用裸 `python3`。**
> 管道依赖 `jieba`、`scikit-learn`、`PyYAML`、`networkx`、`python-frontmatter`。
> 系统自带的 `/usr/bin/python3` 一个都没有，直接 `ModuleNotFoundError`。
> 本机可用环境：`/Users/bo.gong/.venvs/ai-kg/bin/python3`。

## 工作流程

### Step 1: 检查变更

```bash
source "{skill_dir}/.env"
"$KG_PYTHON" "$KG_PROJECT_DIR/check_changes.py"
```

- 退出码 0 = 无变更，流程结束
- 退出码 1 = 有变更，继续 Step 2

### Step 2: 重建知识库

```bash
"$KG_PYTHON" "$KG_PROJECT_DIR/kg-pipeline/build_kb.py"
```

- **全量重建 `kb.sqlite`**（22 篇 / 798 页约 1.7 秒）——刻意不做增量：
  全量重建比维护增量状态更简单，也更不容易出错
- 同时导出**精简的 `graph.json` 视图**（820 节点 / 798 边，约 330KB），
  供 `kb-ingest/verify.py` 与 dashboard 使用
- **不修改 vault**

> ⚠️ **不要再跑 `pipeline.py` 来更新图谱**。它会把 `graph.json` 重写成旧的
> 120MB 大图，覆盖掉这里的导出视图。旧的图/共现/回写逻辑已由 kb 层取代。
> 如果确实需要它的 frontmatter 回写，跑完 `pipeline.py` 后**必须再跑一次
> `build_kb.py`**，把导出视图恢复回来。
>
> ⚠️ 也**不要用 `pipeline.py --force`**：它会把 state 当空，全量重解析**并回写 vault**。

### Step 2b（可选）: 更新向量

只在启用了向量检索时需要。默认关闭，见 `AI-KG/docs/KB_IMPROVEMENT_PLAN.md`。

```bash
"$KG_PYTHON" "$KG_PROJECT_DIR/kg-pipeline/build_vectors.py"
```

只编码 `model` 标记不一致的段（增量）；852 段约 10 分钟（CPU）。

### Step 3: 同步 Dashboard

如果之前运行过 dashboard，同步更新可视化数据：

```bash
"$KG_PYTHON" "$KG_PROJECT_DIR/convert_for_dashboard.py"
```

## 增量语义（重要）

「变更判定」与「回写」都是增量的，只有建图用全量数据：

| 步骤 | 范围 |
|------|------|
| 扫描 + hash 比对 | 全量列目录（不解析内容） |
| 解析 `.md` | **仅变更文件** |
| 回写 frontmatter / wiki-link / `.bak` | **仅变更文件** |
| `index_state.json` | **仅变更条目**（未变更的原样保留） |
| 内存建图 | 用全部文档的提取结果 |
| 导出 `graph.json` | 整体写出（它是一张整图的产物） |

**为什么建图必须用全量**：`fm_related` 的目标解析要遍历所有文档，标签共现权重和文档相似度本身就是全局统计量。如果只用变更文件建图，`graph.json` 会被写成一个只含本轮变更文档的残缺图 —— 这正是曾出现过的故障（曾导致 12 篇文档中 8 篇从图谱里消失，问答检索不到）。现在每篇文档的提取结果都随 `index_state.json` 一起持久化，未变更文件无需重新解析。

## 注意事项

- 未变更的 `.md` 不会被打开、不会被改写、不会产生新 `.bak`
- 如果 `index_state.json` 里某条记录缺少提取结果（升级到本机制之前的存量记录，或提取器结构变更），该文件会被视同需要解析并回填 —— 首次运行可能解析全部文件，之后才是纯增量
- 回写 .md 前自动创建 `.bak` 备份文件
- 删除文档后，下一轮会把它从图谱中移除并清理 state 记录
- **标签禁用词由管道兜底**（`kg-pipeline/config.yaml` 的 `exclude_tags`）：管道从**正文**派生实体再回写成 tags，所以「封面/目录/附录/分隔页」这类结构性词汇、以及公司名，会从正文（页脚、`About <公司>` 章节）渗进 frontmatter 并沉淀下来。上游 `ppt-extract` 有同样的禁用词表，但**回写发生在上游之后**，只在上游过滤挡不住——实测一次批量入库后 7 篇文档的 tags 里都有这类词。
  - **匹配方式是「包含」而非「等于」**：这类词会组合出现。实测精确匹配只挡住 `Accenture`，却漏掉了 `Accenture内部`（两篇文档）和 `章节分隔页`。改成子串匹配后全部拦住，且不影响 `AI架构`、`RAG`、`Ontology Design` 这类正常标签。
  - 增删禁用词改 `exclude_tags` 即可，无需改代码
- 如果 vault 目录不存在，检查 `kg-pipeline/config.local.yaml` 中的 `vault_path` 配置
- 更新后刷新 dashboard 页面即可看到新数据
- 图健康自检：`graph.json` 的 document 节点数应等于 vault 内 `.md` 数量，不等就是图谱被截断了
