#!/bin/bash
# ============================================================
# ppt-extract 批量 OCR（第四步）
#
# 对已生成的 asset/slide_*.png 跑 Tesseract（chi_sim+eng），
# 产出 {output_dir}/ocr_slide_NN.txt。
#
# 用法:
#   batch_ocr.sh <源根目录> [<更多源根目录> ...]
#
# OCR 在这套流程里的定位是**辅助验证**，不是主数据源（准确率约 85-90%，
# 中英混合密集文本更低）。因此它可以与撰写并行、也可以后补。
#
# 幂等：已存在的 ocr_slide_NN.txt 会跳过。
# ============================================================
set -u

if [ $# -lt 1 ]; then
  echo "用法: $(basename "$0") <源根目录> [<更多源根目录> ...]" >&2
  exit 1
fi

if ! command -v tesseract >/dev/null 2>&1; then
  echo "✗ 未找到 tesseract。安装：brew install tesseract tesseract-lang" >&2
  exit 1
fi

for root in "$@"; do
  [ -d "$root" ] || { echo "⚠️  跳过不存在的目录: $root" >&2; continue; }

  # 遍历 {root}/*/asset/slide_*.png，即各份文档的输出目录
  for out in "$root"/*/; do
    out="${out%/}"
    name="$(basename "$out")"
    [ -d "$out/asset" ] || continue

    total=$(ls "$out"/asset/slide_*.png 2>/dev/null | wc -l | tr -d ' ')
    [ "$total" -gt 0 ] || continue

    done=$(ls "$out"/ocr_slide_*.txt 2>/dev/null | wc -l | tr -d ' ')
    if [ "$done" -ge "$total" ]; then
      echo "$name: OCR 已完成 ($done/$total)，跳过"
      continue
    fi

    echo "########## $name  ($total 页，已有 $done)"
    i=0
    for img in "$out"/asset/slide_*.png; do
      [ -e "$img" ] || continue
      b="$(basename "$img" .png)"; n="${b#slide_}"
      tgt="$out/ocr_slide_$n"
      [ -s "$tgt.txt" ] && continue
      tesseract "$img" "$tgt" -l chi_sim+eng >/dev/null 2>&1
      i=$((i+1))
    done
    echo "  新完成 $i 页"
  done
done

echo
echo "===== 批量 OCR 完成 ====="
