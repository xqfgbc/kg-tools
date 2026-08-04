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

# 安装了 pdfplumber 的 Python 解释器路径
# 推荐使用虚拟环境或 conda 环境中的 Python
# 确保该 Python 已安装: pip install pdfplumber
PDFPLUMBER_PYTHON="python3"
