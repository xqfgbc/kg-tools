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

AI-KG 项目路径通过 `.env` 文件配置（本地文件，不提交 Git）：

```bash
# 首次使用：复制配置模板
cp .env.example .env
# 编辑 .env，设置你的 AI-KG 项目路径
```

```bash
# .env 内容
KG_PROJECT_DIR=/path/to/AI-KG
```

Skill 执行时通过 `source .env` 加载 `$KG_PROJECT_DIR` 变量。

## 工作流程

### Step 1: 检查变更

```bash
source "{skill_dir}/.env"
python3 "$KG_PROJECT_DIR/check_changes.py"
```

- 退出码 0 = 无变更，流程结束
- 退出码 1 = 有变更，继续 Step 2

### Step 2: 更新图谱

```bash
python3 "$KG_PROJECT_DIR/kg-pipeline/pipeline.py"
```

管道会：
- 扫描 vault 中所有 .md 文件
- 对比 index_state.json 中的 mtime + hash，仅处理变更文件
- 提取 frontmatter tags、inline tags（🏷️ 标签块）、wiki-links、标题层级
- 实体归一化（别名映射）
- 计算标签共现和文档相似度
- 回写 enriched frontmatter 到 .md 文件（有 .bak 备份）
- 高置信度自动注入 [[wiki-links]]
- 导出 graph.json
- 更新 index_state.json

### Step 3: 同步 Dashboard

如果之前运行过 dashboard，同步更新可视化数据：

```bash
python3 "$KG_PROJECT_DIR/convert_for_dashboard.py"
```

## 注意事项

- 管道是**增量更新**，只处理变化文件，不会重复扫描
- 首次运行前如果 index_state.json 为空，会全量构建
- 回写 .md 前自动创建 `.bak` 备份文件
- 如果 vault 目录不存在，检查 `kg-pipeline/config.yaml` 中的 `vault_path` 配置
- 更新后刷新 dashboard 页面即可看到新数据
