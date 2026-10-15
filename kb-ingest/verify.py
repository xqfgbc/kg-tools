#!/usr/bin/env python3
"""
kb-ingest 验收检查。

把「入库是否真的成功」变成可判定的断言，覆盖三类失败：

  1. 图谱被增量截断   —— graph.json 的文档数 < vault 里的 .md 数
  2. 文档没进图谱     —— 指定文档不在 graph.json 的 document 节点里
  3. 产物不完整       —— md 不存在 / frontmatter 解析失败 / 缺 title /
                        关联章节重复 / 图片引用指向不存在的文件

用法:
    verify.py                      检查图谱覆盖完整性
    verify.py --doc <vault相对路径>  额外检查某篇文档
"""
import argparse
import json
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__))))

# ppt-extract 规定标签里不得出现的词。这些词一旦作为标签进入文档，
# 图谱管道会把它们当成实体抽出来、再回写进 frontmatter，之后就固化下来，
# 所以必须在入库时就拦住。
BANNED_TAGS = ('埃森哲', 'Accenture', 'accenture', '目录', '分隔页',
               '封面', '附录', '占位页')


def graph_path() -> str:
    return os.path.join(os.environ["KG_PROJECT_DIR"], "kg-pipeline-data", "graph.json")


def load_graph_doc_ids() -> set:
    with open(graph_path(), "r", encoding="utf-8") as f:
        g = json.load(f)
    return {n["id"] for n in g["nodes"] if n.get("type") == "document"}


def scan_vault_md(vault: str):
    """与管道一致：跳过隐藏目录和 asset/。"""
    out = {}
    for root, dirs, files in os.walk(vault):
        dirs[:] = [d for d in dirs if not d.startswith(".")]
        if os.path.basename(root) == "asset":
            continue
        for fn in files:
            if fn.endswith(".md"):
                abs_p = os.path.join(root, fn)
                out[os.path.relpath(abs_p, vault)] = abs_p
    return out


def parse_frontmatter(text: str):
    """返回 frontmatter 字典；无 frontmatter 返回 None。"""
    if not text.startswith("---"):
        return None
    end = text.find("\n---", 3)
    if end == -1:
        return None
    import yaml
    try:
        return yaml.safe_load(text[3:end]) or {}
    except Exception as e:
        raise ValueError(f"frontmatter YAML 解析失败: {e}")


def check_graph_coverage(vault: str, failures: list, notes: list):
    doc_ids = load_graph_doc_ids()
    md_files = scan_vault_md(vault)
    notes.append(f"图谱 document 节点: {len(doc_ids)}")
    notes.append(f"vault 内 .md 文件:  {len(md_files)}")
    if len(doc_ids) != len(md_files):
        failures.append(
            f"图谱与 vault 文档数不一致（{len(doc_ids)} vs {len(md_files)}）"
            f" —— 图谱可能被增量截断，运行 /kg-update 重建"
        )
    return doc_ids, md_files


def check_doc(rel_path: str, vault: str, doc_ids: set, failures: list, notes: list):
    abs_p = os.path.join(vault, rel_path)
    if not os.path.isfile(abs_p):
        failures.append(f"{rel_path}: 文件不存在")
        return

    with open(abs_p, "r", encoding="utf-8") as f:
        text = f.read()

    # 1. frontmatter + title
    try:
        fm = parse_frontmatter(text)
    except ValueError as e:
        failures.append(f"{rel_path}: {e}")
        fm = None
    if fm is None:
        failures.append(f"{rel_path}: 缺 YAML frontmatter")
    else:
        if not fm.get("title"):
            failures.append(f"{rel_path}: frontmatter 缺 title（图谱节点标题会退化成路径）")
        if not fm.get("tags"):
            failures.append(f"{rel_path}: frontmatter 缺 tags（不会参与图谱连通）")

    # 6. 禁用标签：frontmatter + 每页 inline 标签都要查
    banned_hits = set()
    if fm:
        for t in (fm.get("tags") or []):
            if str(t) in BANNED_TAGS:
                banned_hits.add(str(t))
    for line in re.findall(r"^> \*\*🏷️ 标签\*\*: (.*)$", text, flags=re.MULTILINE):
        for t in re.findall(r"`([^`]+)`", line):
            if t in BANNED_TAGS:
                banned_hits.add(t)
    if banned_hits:
        failures.append(
            f"{rel_path}: 标签含禁用词 {sorted(banned_hits)}"
            f" —— 会被图谱抽成实体并回写进 frontmatter，需在源 md 里改掉后重跑管道"
        )

    # 2. title == 文件名 == 目录名
    stem = os.path.splitext(os.path.basename(rel_path))[0]
    if stem != os.path.basename(os.path.dirname(rel_path)):
        notes.append(f"  提示: 文件名与目录名不一致（{stem} ≠ {os.path.dirname(rel_path)}）")

    # 3. 关联章节只应有一个
    n_rel = len(re.findall(r"^## 🔗 (?:关联文档|相关文档)", text, flags=re.MULTILINE))
    if n_rel == 0:
        failures.append(f"{rel_path}: 没有关联文档章节")
    elif n_rel > 1:
        failures.append(f"{rel_path}: 有 {n_rel} 个关联文档章节（应为 1）")

    # 4. 图片引用都存在
    missing = []
    for m in re.finditer(r"!\[[^\]]*\]\((?!https?:)([^)]+)\)", text):
        target = m.group(1).split("#")[0].strip()
        if not os.path.isfile(os.path.join(os.path.dirname(abs_p), target)):
            missing.append(target)
    if missing:
        failures.append(
            f"{rel_path}: {len(missing)} 个图片引用找不到文件，例如 {missing[0]}"
        )

    # 5. 进了图谱
    doc_id = "doc:" + rel_path
    if doc_id in doc_ids:
        notes.append(f"  ✅ 在图谱中: {doc_id}")
    else:
        failures.append(f"{rel_path}: 不在 graph.json 的 document 节点里")

    slides = len(re.findall(r"^## Slide", text, flags=re.MULTILINE))
    if slides:
        notes.append(f"  幻灯片数: {slides}")


def main() -> int:
    parser = argparse.ArgumentParser(description="kb-ingest 验收检查")
    parser.add_argument("--doc", action="append", default=[],
                        help="vault 相对路径，可重复指定")
    args = parser.parse_args()

    vault = os.environ.get("VAULT_PATH")
    if not vault:
        raise SystemExit("VAULT_PATH 未设置（先 source kb-ingest/.env）")

    failures: list = []
    notes: list = []

    doc_ids, _ = check_graph_coverage(vault, failures, notes)
    for rel in args.doc:
        check_doc(rel.lstrip("/"), vault, doc_ids, failures, notes)

    for n in notes:
        print(n)

    if failures:
        print(f"\n❌ 未通过 {len(failures)} 项：")
        for f in failures:
            print(f"  - {f}")
        return 1

    print("\n✅ 验收通过")
    return 0


if __name__ == "__main__":
    sys.exit(main())
