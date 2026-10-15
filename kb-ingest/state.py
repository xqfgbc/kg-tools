#!/usr/bin/env python3
"""
kb-ingest 进度清单管理。

记录每个源文档走到了哪一步，让整条入库链路可以断点续跑：

  - 源文件没变、且已走到 ingested  → 跳过
  - 上次中断在提取之后            → 从「融入 Obsidian」继续
  - 源文件改了（hash 变化）        → 从「提取」重新开始

状态文件位置：$KB_STATE_DIR/kb-ingest-state.json
默认 $HOME/Documents/accenture/kb-work/

用法:
    state.py scan <root> [<root>...]        列出候选文档及其当前状态
    state.py mark <source> <stage> [--vault-path PATH]
    state.py status
    state.py reset <source>
"""
import argparse
import hashlib
import json
import os
import sys
from datetime import datetime, timezone

# 提取产物必须等于这个阶段才认为「提取已完成」
STAGES = ("extracted", "ingested")
SOURCE_EXTS = (".pptx", ".pdf")


def state_path() -> str:
    """
    进度清单的位置：$KB_STATE_DIR/kb-ingest-state.json
    默认落在本 skill 目录下的 .local/（已 gitignore）。

    这是**运行时状态**，不是源码：每跑一次入库都会改写，且只对本机有意义。
    所以它不入版本管理——放仓库里只会让工作区一直脏着，换机时还会误导。
    """
    default = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".local")
    d = os.environ.get("KB_STATE_DIR") or default
    os.makedirs(d, exist_ok=True)
    return os.path.join(d, "kb-ingest-state.json")


def load_state() -> dict:
    p = state_path()
    if not os.path.exists(p):
        return {}
    try:
        with open(p, "r", encoding="utf-8") as f:
            return json.load(f)
    except json.JSONDecodeError as e:
        raise SystemExit(
            f"进度清单解析失败: {p}\n  {e}\n"
            f"  删除该文件可重新开始（已完成的文档会被重新处理一遍）。"
        )


def save_state(state: dict) -> None:
    """原子写，避免中途失败留下截断的 JSON。"""
    p = state_path()
    tmp = p + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(state, f, ensure_ascii=False, indent=2, sort_keys=True)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, p)


def file_hash(path: str) -> str:
    h = hashlib.md5()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def iter_sources(roots):
    """枚举候选源文档，跳过 Office 临时文件（~$ 开头）。"""
    for root in roots:
        if os.path.isfile(root):
            if root.lower().endswith(SOURCE_EXTS):
                yield os.path.abspath(root)
            continue
        if not os.path.isdir(root):
            print(f"⚠️  路径不存在，跳过: {root}", file=sys.stderr)
            continue
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = [d for d in dirnames if not d.startswith(".")]
            # 源根下会混有 ppt-extract 的产物目录（{name}/{name}.pdf、{name}.md、asset/…）。
            # 若整个目录就是某个已提取文档的输出目录，直接跳过整棵子树，
            # 否则中间 PDF 会被当成一份新的待处理文档。
            if is_extract_output_dir(dirpath):
                dirnames[:] = []
                continue
            for fn in sorted(filenames):
                if fn.startswith("~$"):
                    continue
                if fn.lower().endswith(SOURCE_EXTS):
                    yield os.path.join(dirpath, fn)


def is_extract_output_dir(path: str) -> bool:
    """
    判断该目录是否是 ppt-extract 的输出目录。

    只靠扩展名无法区分「用户提供的源 PDF」与「PPTX 转出的中间 PDF」——
    两者都是 .pdf。必须靠目录结构：ppt-extract 的输出目录布局是

        {name}/
        ├── {name}.pdf          ← 中间产物（PPTX 输入时）
        ├── extraction_raw.txt
        └── asset/slide_NN.png

    判据用「存在 {name}.pdf」**加上**「存在 extraction_raw.txt 或 asset/」。

    ⚠️ 不要用 {name}.md 是否存在来判断。撰写（第六步）是提取之后才做的，
    在撰写完成前 .md 并不存在 —— 用它判断会漏掉正在处理中的文档，
    于是 {name}.pdf 被当成新的源文件处理，又被写进 {name}/{name}/，
    下次再扫又发现更深一层……每跑一次就多嵌套一层。
    """
    stem = os.path.basename(path.rstrip(os.sep))
    if not stem:
        return False
    if not os.path.isfile(os.path.join(path, stem + ".pdf")):
        return False
    return (os.path.isfile(os.path.join(path, "extraction_raw.txt"))
            or os.path.isdir(os.path.join(path, "asset")))


def derived_paths(source: str) -> dict:
    """ppt-extract 的输出约定：{文件所在目录}/{name}/{name}.md"""
    name = os.path.splitext(os.path.basename(source))[0]
    out_dir = os.path.join(os.path.dirname(source), name)
    return {
        "name": name,
        "extract_dir": out_dir,
        "extract_md": os.path.join(out_dir, name + ".md"),
    }


def cmd_scan(args) -> int:
    state = load_state()
    rows = []
    for source in iter_sources(args.roots):
        info = derived_paths(source)
        rec = state.get(source, {})
        current_hash = file_hash(source)

        if not rec:
            status, stage = "todo", None
        elif rec.get("source_hash") != current_hash:
            status, stage = "source-changed", rec.get("stage")
        elif rec.get("stage") == "ingested":
            status, stage = "done", "ingested"
        else:
            status, stage = "resume", rec.get("stage")

        rows.append({
            "source": source,
            "status": status,
            "stage": stage,
            "source_hash": current_hash,
            "vault_path": rec.get("vault_path"),
            **info,
        })

    json.dump(rows, sys.stdout, ensure_ascii=False, indent=2)
    print()

    todo = [r for r in rows if r["status"] != "done"]
    print(f"# 候选 {len(rows)} 份，待处理 {len(todo)} 份", file=sys.stderr)
    for r in rows:
        print(f"  {r['status']:<14} {r['name']}", file=sys.stderr)
    return 0


def cmd_mark(args) -> int:
    state = load_state()
    source = os.path.abspath(args.source)

    if args.stage == "reset":
        state.pop(source, None)
        save_state(state)
        print(f"已重置: {source}")
        return 0

    if args.stage not in STAGES:
        raise SystemExit(f"未知阶段: {args.stage}（可选: {', '.join(STAGES)}, reset）")

    rec = state.get(source, {})
    rec["source_hash"] = file_hash(source)
    rec["stage"] = args.stage
    rec["updated_at"] = datetime.now(timezone.utc).isoformat(timespec="seconds")
    if args.vault_path:
        rec["vault_path"] = args.vault_path
    state[source] = rec
    save_state(state)
    print(f"{os.path.basename(source)} → {args.stage}")
    return 0


def cmd_status(args) -> int:
    state = load_state()
    print(f"清单: {state_path()}")
    print(f"记录: {len(state)} 份\n")
    for source in sorted(state):
        rec = state[source]
        print(f"  [{rec.get('stage', '?'):<9}] {rec.get('name', os.path.basename(source))}")
        if rec.get("vault_path"):
            print(f"              → {rec['vault_path']}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="kb-ingest 进度清单管理")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_scan = sub.add_parser("scan", help="列出候选文档及其状态")
    p_scan.add_argument("roots", nargs="+", help="源文件或文件夹")
    p_scan.set_defaults(func=cmd_scan)

    p_mark = sub.add_parser("mark", help="更新某份文档的阶段")
    p_mark.add_argument("source")
    p_mark.add_argument("stage", help="extracted | ingested | reset")
    p_mark.add_argument("--vault-path", dest="vault_path", default=None,
                        help="该文档在 vault 中的最终路径")
    p_mark.set_defaults(func=cmd_mark)

    p_status = sub.add_parser("status", help="显示当前清单")
    p_status.set_defaults(func=cmd_status)

    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
