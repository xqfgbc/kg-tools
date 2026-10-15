#!/bin/bash
# ============================================================
# ppt-extract 批量提取（第一/二/三步的自动化）
#
#   PPTX → PDF → PNG(150DPI) → python-pptx 结构化提取
#
# 用法:
#   batch_extract.sh <源根目录> [<更多源根目录> ...]
#
# 输出沿用单文件约定：{文件所在目录}/{name}/，内含
#   {name}.md（由第六步撰写，本脚本不生成）、{name}.pdf、
#   extraction_raw.txt、asset/slide_NN.png
#
# 幂等可续跑：已完成的产物会跳过。
# 逐份串行处理，并且**全局加锁**——两个实例同时跑会争抢同一份输出。
# OCR 不在本脚本内，见 batch_ocr.sh。
# ============================================================
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/config.sh"
SOFFICE="$LIBREOFFICE_PATH/Contents/MacOS/soffice"

if [ $# -lt 1 ]; then
  echo "用法: $(basename "$0") <源根目录> [<更多源根目录> ...]" >&2
  echo "例如: $(basename "$0") ~/Documents/accenture/carlsberg/资料" >&2
  exit 1
fi

# --- 并发保护 --------------------------------------------------------------
# 两个实例同时跑会各自启动 LibreOffice 写同一个输出目录，产物互相覆盖。
# 这不是假想：真发生过，两个进程抢同一份 PDF。
LOCK="/tmp/ppt-extract-batch.lock"
if ! mkdir "$LOCK" 2>/dev/null; then
  echo "✗ 另一个批量提取正在运行（锁: ${LOCK}）。" >&2
  echo "  等它结束，或确认已无残留进程后删除该目录再试：rmdir $LOCK" >&2
  exit 1
fi
trap 'rm -rf "$LOCK"' EXIT

# --- 工具函数 --------------------------------------------------------------

# 取 PDF 页数；非 PDF 或损坏时返回空。用于识别中断留下的半截文件。
pdf_pages() {
  [ -f "$1" ] || return
  command -v pdfinfo >/dev/null 2>&1 || { echo "?"; return; }
  pdfinfo "$1" 2>/dev/null | awk '/^Pages:/{print $2}'
}

# 统计 asset 下的 PNG 数量
png_count() {
  [ -d "$1/asset" ] || { echo 0; return; }
  ls "$1"/asset/slide_*.png 2>/dev/null | wc -l | tr -d ' '
}

# 判断 OLE2 文件是否为 DRM/IRM 加密（Microsoft Purview / Azure 信息保护等）。
#
# 这类文件的真实内容在 `EncryptedPackage` 流里，没有 `PowerPoint Document` 流。
# **LibreOffice 不支持 IRM**：给它转换不会报错，而是 100% CPU 空转十几分钟、零产出，
# 看起来像「文件很大所以慢」。必须提前识别、直接跳过。
# OLE2 的流名以 UTF-16LE 存在目录里，因此直接在字节流里搜该编码的流名即可，
# 不依赖 olefile。
is_drm_protected() {
  "$PDFPLUMBER_PYTHON" - "$1" <<'PY' 2>/dev/null
import sys
try:
    data = open(sys.argv[1], 'rb').read()
except OSError:
    sys.exit(1)
signals = [s.encode('utf-16-le') for s in
           ('EncryptedPackage', 'DRMEncryptedDataSpace', 'DRMEncryptedTransform')]
sys.exit(0 if any(s in data for s in signals) else 1)
PY
}

# 按魔数判断真实格式。**扩展名不可信** —— 遇到过老式二进制 .ppt 被改名成 .pptx：
# 此时 LibreOffice 能转 PDF（图片通道正常），但 python-pptx 打不开 zip，
# 结构化通道直接失败，最终只有一堆 PNG、没有可读内容。
# 返回: zip(.pptx) | ole2(老式.ppt) | pdf | other
detect_format() {
  local magic
  magic="$(head -c 8 "$1" 2>/dev/null | od -An -tx1 | tr -d ' \n')"
  case "$magic" in
    d0cf11e0a1b11ae1*) echo ole2 ;;   # OLE2 复合文档 = 老式 .ppt/.doc
    504b0304*)         echo zip  ;;   # OOXML (.pptx/.docx/.xlsx)
    25504446*)         echo pdf  ;;   # %PDF-
    *)                 echo other ;;
  esac
}

# --- 枚举待处理源文件 -------------------------------------------------------
# 关键：从文件系统枚举，不要手抄文件名——文件名里可能有 U+00A0 不换行空格
# 之类的不可见字符，手写会静默漏掉整份文档。
list="$(mktemp)"
trap 'rm -rf "$LOCK" "$list"' EXIT
for root in "$@"; do
  if [ ! -d "$root" ]; then
    echo "⚠️  跳过不存在的目录: $root" >&2
    continue
  fi
  find "$root" -type f \( -name '*.pptx' -o -name '*.pdf' \) ! -name '~$*' -print >> "$list"
done
sort -o "$list" "$list"

echo "发现 $(wc -l < "$list" | tr -d ' ') 个候选源文件"

while IFS= read -r src; do
  [ -n "$src" ] || continue

  # 跳过 ppt-extract 自己的产物目录：其中 {name}/{name}.pdf 是中间产物，
  # 不是新的待处理文档。
  #
  # ⚠️ 判据不要用 {name}.md 是否存在 —— 撰写（第六步）在提取之后才做，
  # 撰写完成前 .md 不存在，判据会失效，于是 {name}.pdf 被当成新源文件处理、
  # 又写进 {name}/{name}/，下次再扫发现更深一层……**每跑一次多嵌套一层**。
  # 改用「存在 {name}.pdf」+「存在 extraction_raw.txt 或 asset/」的组合。
  dir="$(dirname "$src")"
  stem="$(basename "$dir")"
  if [ -f "$dir/$stem.pdf" ] && { [ -f "$dir/extraction_raw.txt" ] || [ -d "$dir/asset" ]; }; then
    echo "跳过提取产物目录: $src"
    continue
  fi

  name="$(basename "$src")"; name="${name%.*}"
  out="$dir/$name"
  echo
  echo "########## $name"

  # DRM/IRM 加密的文件无法提取，而且会让 LibreOffice 空转——提前拦掉
  if is_drm_protected "$src"; then
    echo "  ✗ 该文件受 DRM/IRM 加密保护（Microsoft Purview / Azure 信息保护等），无法提取。" >&2
    echo "    内容在 EncryptedPackage 流里，需有权限的账号在 PowerPoint 中导出**未加密副本**后重试。" >&2
    echo "    （LibreOffice 不支持 IRM，直接转换会 100% CPU 空转且零产出。）" >&2
    continue
  fi

  # 用真实格式而非扩展名决定走哪条通道
  FMT="$(detect_format "$src")"
  case "$FMT" in
    zip)   INPUT_TYPE="pptx" ;;
    ole2)  INPUT_TYPE="ppt"  ;;
    pdf)   INPUT_TYPE="pdf"  ;;
    *)     echo "  ✗ 无法识别的文件格式（魔数不匹配 pptx/ppt/pdf），跳过"; continue ;;
  esac
  [ "$INPUT_TYPE" = "ppt" ] && echo "  ⚠️ 扩展名是 .pptx，但文件实际是老式二进制 .ppt"

  # --- 第 2a 步：得到 PDF ---
  if [ "$INPUT_TYPE" = "pdf" ]; then
    if [ ! -f "$out/$name.pdf" ]; then
      echo "  [1/4] PDF 输入，跳过 LibreOffice 转换"
      mkdir -p "$out/asset"
      cp "$src" "$out/$name.pdf"
    fi
  else
    # 已存在的 PDF 必须先验证：中断可能留下 0 字节或半截文件，
    # 仅凭 [ -f ] 判断会把它当成「已完成」，后面 pdftoppm 直接失败或产出残缺。
    if [ -f "$out/$name.pdf" ] && [ -z "$(pdf_pages "$out/$name.pdf")" ]; then
      echo "  [1/4] ⚠️ 已有 PDF 无效（可能上次中断留下），重新转换"
      rm -f "$out/$name.pdf"
    fi
    if [ -f "$out/$name.pdf" ]; then
      echo "  [1/4] PDF 已存在且有效，跳过"
    else
      if [ ! -x "$SOFFICE" ]; then
        echo "  ✗ 未找到 soffice: ${SOFFICE}（检查 config.sh 的 LIBREOFFICE_PATH）" >&2
        continue
      fi
      echo "  [1/4] PPTX → PDF ..."
      mkdir -p "$out/asset"
      "$SOFFICE" --headless --convert-to pdf --outdir "$out" "$src" 2>&1 | tail -1
      if [ -z "$(pdf_pages "$out/$name.pdf")" ]; then
        echo "  ✗ 转换失败，未得到有效 PDF，跳过" >&2
        continue
      fi
    fi
  fi

  want="$(pdf_pages "$out/$name.pdf")"
  echo "       PDF 页数: $want"

  # --- 第 2b/2c 步：PDF → PNG，规范化为 slide_NN.png ---
  have="$(png_count "$out")"
  if [ "$want" != "?" ] && [ "$have" = "$want" ]; then
    echo "  [2/4] PNG 已齐全（${have}），跳过"
  else
    if [ "$have" != "0" ]; then
      echo "  [2/4] PNG 数量不符（有 ${have}，应为 ${want}），重新渲染"
      rm -f "$out"/asset/slide*.png
    else
      echo "  [2/4] PDF → PNG ..."
    fi
    mkdir -p "$out/asset"
    pdftoppm -png -r 150 "$out/$name.pdf" "$out/asset/slide"
    # ⚠️ 必须用 10#$n 强制十进制。
    # pdftoppm 按总页数补零（>9 页时输出 slide-08.png），而 bash 的 printf %d
    # 把前导 0 当八进制："08"/"09" 非法 → 报 invalid number 并按 0 处理 →
    # 两次都输出 slide_00.png，后者覆盖前者。结果是第 8、9 页图片凭空消失，
    # 且脚本不报错。（zsh 的 printf 不这么做，同一段代码在 zsh 里反而正常。）
    ( cd "$out/asset" && for p in slide-*.png; do
        [ -e "$p" ] || continue
        n="${p#slide-}"; n="${n%.png}"
        printf -v new "slide_%02d.png" "$((10#$n))"
        [ "$p" = "$new" ] || mv "$p" "$new"
      done )
  fi
  pages="$(png_count "$out")"
  echo "       PNG: $pages 张"

  # --- 第 3a 步：老式 .ppt 先转成真正的 .pptx ---
  # 为什么不直接用 PDF 通道：pdfplumber 拿不到形状类型（GROUP/LINE/CONNECTOR）、
  # 连接线信息和字体层级，结构化质量明显低于 python-pptx。
  # LibreOffice 读老式 .ppt 没问题，转一道即可保住质量更好的通道。
  STRUCT_SRC="$src"
  if [ "$INPUT_TYPE" = "ppt" ]; then
    if [ ! -s "$out/$name.pptx" ]; then
      echo "  [3a/4] 转换为真正的 .pptx（供结构化通道使用）..."
      "$SOFFICE" --headless --convert-to pptx --outdir "$out" "$src" 2>&1 | tail -1
    fi
    if [ -s "$out/$name.pptx" ]; then
      STRUCT_SRC="$out/$name.pptx"
    else
      echo "  ⚠️ 转换失败，退回 PDF 通道（结构信息会较少）" >&2
      INPUT_TYPE="pdf"
    fi
  fi

  # --- 第 3 步：结构化提取 ---
  if [ -s "$out/extraction_raw.txt" ]; then
    echo "  [3/4] extraction_raw.txt 已存在，跳过"
  else
    echo "  [3/4] 结构化提取（$INPUT_TYPE 通道）..."
    if [ "$INPUT_TYPE" = "pdf" ]; then
      cp "$SCRIPT_DIR/extract_pdf.py" "$out/extract_pdf.py"
      "$PDFPLUMBER_PYTHON" "$out/extract_pdf.py" "$out/$name.pdf" > "$out/extraction_raw.txt" 2>&1
    else
      "$PDFPLUMBER_PYTHON" "$SCRIPT_DIR/extract_pptx.py" "$STRUCT_SRC" > "$out/extraction_raw.txt" 2>&1
    fi
  fi
  echo "       extraction_raw.txt: $(wc -l < "$out/extraction_raw.txt" | tr -d ' ') 行"

  # 结构化通道必须真的提取到内容——空文件说明通道选错了或文件损坏，
  # 不能当成「提取完成」放行（否则后续会产出一份没有正文的 md）。
  # 注意两条通道的首行标记不同：pptx 通道是 SLIDE_COUNT，pdf 通道是 PAGE_COUNT。
  # 只认其中一个会对另一条通道误报。
  if ! grep -qE '^(SLIDE_COUNT|PAGE_COUNT):' "$out/extraction_raw.txt" 2>/dev/null; then
    echo "  ✗ 结构化提取未产出有效内容（无 SLIDE_COUNT 标记），请检查源文件" >&2
    head -3 "$out/extraction_raw.txt" | sed 's/^/      /' >&2
  fi

  # --- 自检：这三项不通过就别往下走 ---
  ok=1
  if ls "$out"/asset/slide-*.png >/dev/null 2>&1; then
    echo "  ✗ 存在未重命名的 slide-*.png" >&2; ok=0
  fi
  if [ -f "$out/asset/slide_00.png" ]; then
    echo "  ✗ 出现 slide_00.png —— printf 八进制 bug 的症状" >&2; ok=0
  fi
  if [ "$want" != "?" ] && [ "$pages" != "$want" ]; then
    echo "  ✗ PNG 数（${pages}）≠ PDF 页数（${want}）" >&2; ok=0
  fi
  if [ "$ok" = "1" ]; then
    echo "  [4/4] ✅ 结构性产物就绪（$pages 页）"
  else
    echo "  → 删除 $out/asset/ 下的 PNG 后重跑本脚本" >&2
  fi
done < "$list"

echo
echo "===== 批量提取完成 ====="
echo "下一步：batch_ocr.sh 跑 OCR（可选），然后按 AUTHORING_BRIEF.md 撰写 {name}.md"
