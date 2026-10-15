#!/usr/bin/env python3
"""
对账：源文件 vs 知识库。

回答「哪些文件还没进知识库」，并指出反向问题（vault 里有、源里找不到的文档）。

用法:
    audit.py                 # 用 .env 里的 SOURCE_ROOTS
    audit.py <目录> [<目录>...]

退出码: 0 = 全部入库；1 = 存在未入库或异常项。

判据分三层，缺一层都算没进库：
    1. 源目录里有该文件
    2. kb-ingest-state.json 记录 stage=ingested
    3. vault 里存在对应 .md（且在图谱里 —— 由 --graph 检查，需读 graph.json）
"""
import argparse
import json
import os
import re
import sys

SOURCE_EXTS = ('.pptx', '.pdf')

# `Extract output` 目录的判据：目录名 == 其中的 .pdf 名，且有 extraction_raw.txt 或 asset/
# （与 state.py / batch_extract.sh 保持一致；不要用 .md 判断，撰写在提取之后）


def is_extract_output_dir(path):
    if not os.path.isdir(path):
        return False
    stem = os.path.basename(path.rstrip(os.sep))
    if not stem:
        return False
    if not os.path.isfile(os.path.join(path, stem + '.pdf')):
        return False
    return (os.path.isfile(os.path.join(path, 'extraction_raw.txt'))
            or os.path.isdir(os.path.join(path, 'asset')))


def magic_kind(path):
    """按魔数判真实格式——扩展名不可信。"""
    try:
        with open(path, 'rb') as f:
            head = f.read(8)
    except OSError:
        return 'unreadable'
    if head.startswith(b'\x50\x4b\x03\x04'):
        return 'zip'            # 真 OOXML
    if head.startswith(b'\xd0\xcf\x11\xe0\xa1\xb1\x1a\xe1'):
        return 'ole2'           # 老式 .ppt 或 DRM 加密容器
    if head.startswith(b'%PDF-'):
        return 'pdf'
    return 'other'


def is_drm(path):
    try:
        data = open(path, 'rb').read()
    except OSError:
        return False
    return any(s.encode('utf-16-le') in data for s in
               ('EncryptedPackage', 'DRMEncryptedDataSpace', 'DRMEncryptedTransform'))


def iter_sources(roots):
    """源根下的一级文档，跳过提取产物目录与 Office 临时文件。"""
    for root in roots:
        if not os.path.isdir(root):
            print(f'⚠️  目录不存在: {root}', file=sys.stderr)
            continue
        for name in sorted(os.listdir(root)):
            if name.startswith('~$') or name.startswith('.'):
                continue
            p = os.path.join(root, name)
            if os.path.isdir(p) and is_extract_output_dir(p):
                continue
            if os.path.isfile(p) and p.lower().endswith(SOURCE_EXTS):
                yield p


def iter_unsupported(roots):
    """源根下的一级文件里，管线不支持的格式（供提示，不算失败）。"""
    for root in roots:
        if not os.path.isdir(root):
            continue
        for name in sorted(os.listdir(root)):
            if name.startswith('~$') or name.startswith('.'):
                continue
            p = os.path.join(root, name)
            if os.path.isfile(p) and not p.lower().endswith(SOURCE_EXTS):
                yield p


def scan_vault_md(vault):
    out = {}
    for root, dirs, files in os.walk(vault):
        dirs[:] = [d for d in dirs if not d.startswith('.') and d != 'asset']
        for f in files:
            if f.endswith('.md'):
                p = os.path.join(root, f)
                out[os.path.relpath(p, vault)] = p
    return out


def main():
    ap = argparse.ArgumentParser(description='源文件 vs 知识库 对账')
    ap.add_argument('roots', nargs='*', help='源根目录（缺省用 $SOURCE_ROOTS，冒号分隔）')
    ap.add_argument('--graph', action='store_true', help='额外核对图谱 document 节点')
    args = ap.parse_args()

    roots = args.roots or [r for r in os.environ.get('SOURCE_ROOTS', '').split(':') if r]
    vault = os.environ.get('VAULT_PATH')
    if not roots:
        sys.exit('未提供源目录，且 $SOURCE_ROOTS 为空')
    if not vault:
        sys.exit('$VAULT_PATH 未设置')

    state_dir = os.environ.get('KB_STATE_DIR') or os.path.join(
        os.path.dirname(os.path.abspath(__file__)), '.local')
    state_path = os.path.join(state_dir, 'kb-ingest-state.json')
    state = {}
    if os.path.exists(state_path):
        try:
            state = json.load(open(state_path, encoding='utf-8'))
        except json.JSONDecodeError as e:
            sys.exit(f'进度清单损坏: {state_path}\n  {e}')

    vault_md = scan_vault_md(vault)
    doc_ids = set()
    if args.graph:
        gp = os.path.join(os.environ.get('KG_PROJECT_DIR', ''), 'kg-pipeline-data/graph.json')
        if os.path.exists(gp):
            doc_ids = {n['id'] for n in json.load(open(gp, encoding='utf-8'))['nodes']
                       if n.get('type') == 'document'}

    rows = []
    for src in iter_sources(roots):
        rec = state.get(src, {})
        stage = rec.get('stage')
        vpath = rec.get('vault_path')
        name = os.path.basename(src)

        in_vault = bool(vpath) and vpath in vault_md
        # 提取产物的目录名取自文件名去扩展名，**与源文件同 stem 的不同来源会指向同一目录**
        # （例如同一份文档既有 DRM 的 .pptx 又有导出的 .pdf）。所以不能靠产物反推是哪个
        # 来源产出的——只能作为「没有清单记录时」的粗略兜底。
        ext_dir = os.path.join(os.path.dirname(src), os.path.splitext(name)[0])

        # DRM 判定必须最优先：这类文件无论有无记录、有无同名产物，都处理不了。
        # 放在后面会被「同 stem 的兄弟文件产出的 md」误判成已完成。
        if is_drm(src):
            status, note = 'blocked', 'DRM/IRM 加密，无法提取（需在 PowerPoint 中导出未加密副本）'
        elif not rec:
            if os.path.isfile(os.path.join(ext_dir, os.path.splitext(name)[0] + '.md')):
                status, note = 'extracted', '提取+撰写完成，未入库（清单无记录）'
            elif os.path.isdir(os.path.join(ext_dir, 'asset')):
                status, note = 'extracting', '提取进行中或未完成'
            else:
                status, note = 'todo', '尚未处理'
        elif stage == 'ingested' and in_vault:
            status, note = 'done', '已入库'
        elif stage == 'ingested' and not in_vault:
            status, note = 'broken', f'清单记为已入库，但 vault 中找不到 {vpath}'
        elif stage == 'extracted':
            status, note = 'extracted', '已提取已撰写，待入库'
        else:
            status, note = 'todo', '尚未处理'

        if status == 'done' and args.graph and vpath and ('doc:' + vpath) not in doc_ids:
            status, note = 'broken', 'vault 中存在，但不在图谱 document 节点里（需跑 /kg-update）'

        rows.append((status, name, magic_kind(src), note))

    # 反向：vault 里有没有源目录之外的文档
    known = {r.get('vault_path') for r in state.values() if r.get('vault_path')}
    orphans = sorted(set(vault_md) - known)

    ICON = {'done': '✅ 已入库', 'extracted': '⏳ 待入库', 'extracting': '⏳ 提取中',
            'todo': '❌ 未处理', 'blocked': '🚫 无法处理', 'broken': '⚠️  异常'}
    order = ['broken', 'extracted', 'extracting', 'todo', 'blocked', 'done']

    print(f"源目录: {', '.join(roots)}")
    print(f"Vault : {vault}")
    print(f"清单  : {state_path}\n")
    for st in order:
        grp = [r for r in rows if r[0] == st]
        if not grp:
            continue
        print(f"{ICON[st]}（{len(grp)}）")
        for _, name, kind, note in grp:
            tag = '' if kind in ('zip', 'pdf') else f'[{kind}] '
            print(f"    {tag}{name}")
            if st not in ('done',):
                print(f"        └ {note}")
        print()

    unsup = list(iter_unsupported(roots))
    if unsup:
        print(f"ℹ️  非 pptx/pdf（管线不处理，仅供参考，{len(unsup)}）")
        for p in unsup:
            print(f"    {os.path.basename(p)}")
        print()

    print(f"Vault 文档 {len(vault_md)} 篇；其中 {len(orphans)} 篇不对应任何已登记源文件：")
    for o in orphans:
        print(f"    {o}")
    if orphans:
        print('    （正常：早期手工放入的文档不会出现在 kb-ingest 清单里）')

    gaps = [r for r in rows if r[0] != 'done']
    print(f"\n源文档 {len(rows)} 份：已入库 {len(rows)-len(gaps)}，"
          f"未入库/异常 {len(gaps)}")
    return 1 if gaps else 0


if __name__ == '__main__':
    sys.exit(main())
