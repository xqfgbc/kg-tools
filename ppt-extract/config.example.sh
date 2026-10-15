# ============================================================
# ppt-extract 环境配置文件
# 复制为 config.sh 并修改为本机实际路径
# config.sh 不应提交到版本管理 (已加入 .gitignore)
# ============================================================

# LibreOffice 安装路径 (用于 PPTX → PDF 转换)
# macOS 常见路径:
#   - 用户级安装: /Users/<用户名>/Applications/LibreOffice.app
#   - 系统级安装: /Applications/LibreOffice.app
LIBREOFFICE_PATH="/Applications/LibreOffice.app"

# 安装了 pdfplumber + python-pptx + Pillow 的 Python 解释器路径
# 推荐使用虚拟环境或 conda 环境中的 Python
# 确保该 Python 已安装: uv pip install --python <该解释器> pdfplumber python-pptx Pillow
# ⚠️ 不要用裸 python3 —— 系统自带的 /usr/bin/python3 通常缺这些依赖
PDFPLUMBER_PYTHON="python3"

# 全链路统一解释器（kg-update / kg-qa 也用同一个环境）
# 除上述三个包外，还需 jieba、scikit-learn、PyYAML、networkx、python-frontmatter
# 本机可用环境: /Users/bo.gong/.venvs/ai-kg/bin/python3
KG_PYTHON="python3"
