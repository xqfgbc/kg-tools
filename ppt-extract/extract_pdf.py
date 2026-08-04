"""
PDF 结构化提取脚本 (pdfplumber 通道)
=====================================
当输入为已从 PPT 转好的 PDF 时，替代 python-pptx 通道。
提取: 文本 + 坐标(x,y) + 字体大小 + 表格 + 图形元素。

用法:
    python extract_pdf.py input.pdf > extraction_pdfplumber.txt 2>&1

注意: 需要使用安装了 pdfplumber 的 Python 环境，参见 config.sh 中的 PDFPLUMBER_PYTHON。
"""

import pdfplumber
import sys

pdf_path = sys.argv[1] if len(sys.argv) > 1 else "input.pdf"

with pdfplumber.open(pdf_path) as pdf:
    print(f"PAGE_COUNT: {len(pdf.pages)}")
    print(f"FILE: {pdf_path}")
    print("=" * 80)

    for i, page in enumerate(pdf.pages):
        page_w_in = page.width / 72
        page_h_in = page.height / 72

        print(f"\n{'='*80}")
        print(f"PAGE {i+1}")
        print(f"Size: {page.width:.0f}x{page.height:.0f} pts = {page_w_in:.1f}x{page_h_in:.1f} inches")
        print(f"{'='*80}")

        # ---- 1. 文本行提取 (含坐标和字体) ----
        # extract_text_lines() 按阅读顺序返回文本行，
        # 每个 line 包含: x0, top, x1, bottom, text, chars[{fontname, size}]
        lines = page.extract_text_lines()
        if lines:
            print(f"\n  --- TEXT LINES ({len(lines)} lines) ---")
            for li, line in enumerate(lines):
                # 坐标转换为英寸 (72 pts/inch)，与 pptx 通道保持一致
                x_in = line['x0'] / 72
                y_in = line['top'] / 72
                w_in = (line['x1'] - line['x0']) / 72
                h_in = (line['bottom'] - line['top']) / 72
                text = line['text'].strip()

                if not text:
                    continue

                # 字体信息 (取第一个字符的字体名和大小)
                font_info = ""
                chars = line.get('chars', [])
                if chars:
                    c = chars[0]
                    fontname = c.get('fontname', '?')
                    fontsize = c.get('size', 0)
                    # 清理字体名前缀 (如 BCDHEE+)
                    if '+' in fontname:
                        fontname = fontname.split('+', 1)[1]
                    font_info = f" | font={fontname} size={fontsize:.0f}pt"

                print(f"    L{li+1}: pos=({x_in:.2f},{y_in:.2f}) size=({w_in:.2f}x{h_in:.2f}) "
                      f"\"{text[:150]}\"{font_info}")

        # ---- 2. 表格提取 ----
        # extract_tables() 返回二维字符串数组，自动检测表格结构
        tables = page.extract_tables()
        if tables:
            print(f"\n  --- TABLES ({len(tables)} found) ---")
            for ti, table in enumerate(tables):
                nrows = len(table)
                ncols = len(table[0]) if table and table[0] else 0
                print(f"  Table {ti+1}: {nrows} rows x {ncols} cols")
                for ri, row in enumerate(table):
                    # 限制每行输出长度，避免日志过大
                    cells = []
                    for c in row:
                        if c:
                            cleaned = c.strip().replace('\n', ' | ')
                            cells.append(cleaned[:200])
                        else:
                            cells.append('')
                    print(f"    ROW {ri}: {' || '.join(cells)}")

        # ---- 3. 字体统计 (用于识别标题/正文层级) ----
        words = page.extract_words()
        if words:
            fonts = {}
            for w in words:
                fn = w.get('fontname', '?')
                fs = round(w.get('height', 0))
                if '+' in fn:
                    fn = fn.split('+', 1)[1]
                key = f"{fn}@{fs}pt"
                fonts[key] = fonts.get(key, 0) + 1

            # 按使用频率降序
            top_fonts = sorted(fonts.items(), key=lambda x: -x[1])[:5]
            print(f"\n  --- FONTS (top {len(top_fonts)}) ---")
            for k, v in top_fonts:
                print(f"    {k}: {v} words")

        # ---- 4. 图形元素 (矩形/线条，辅助判断布局) ----
        rects = page.rects
        page_lines = page.lines
        if len(rects) > 0 or len(page_lines) > 0:
            print(f"\n  --- GRAPHICS: {len(rects)} rectangles, {len(page_lines)} lines ---")
            # 只列出大型矩形 (可能是内容区域边框)
            big_rects = [r for r in rects if (r['width'] * r['height']) > 10000]
            for ri, r in enumerate(big_rects[:5]):
                print(f"    RECT {ri+1}: pos=({r['x0']/72:.1f},{r['top']/72:.1f}) "
                      f"size=({r['width']/72:.1f}x{r['height']/72:.1f})")

print("\n\nDONE")
