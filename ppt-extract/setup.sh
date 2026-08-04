#!/usr/bin/env bash
# ============================================================
# ppt-extract 环境检测与自动安装脚本
# 在首次使用时运行，自动检测或安装所需依赖
# 用法: bash setup.sh
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo ""
echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}  ppt-extract 环境检测与安装${NC}"
echo -e "${CYAN}============================================${NC}"
echo ""

# ---- 检测结果 ----
FOUND_LIBREOFFICE=""
FOUND_PDFPLUMBER_PYTHON=""
MISSING=()

# ============================================================
# 1. 检测系统包管理器
# ============================================================
detect_package_manager() {
    if command -v brew &>/dev/null; then
        echo "brew"
    elif command -v apt-get &>/dev/null; then
        echo "apt"
    elif command -v dnf &>/dev/null; then
        echo "dnf"
    else
        echo "unknown"
    fi
}

PKG_MANAGER=$(detect_package_manager)
echo -e "📦 包管理器: ${GREEN}$PKG_MANAGER${NC}"

# ============================================================
# 2. 检测/安装 pdftoppm (poppler)
# ============================================================
echo ""
echo -n "🔍 pdftoppm ... "
if command -v pdftoppm &>/dev/null; then
    echo -e "${GREEN}已安装 ($(pdftoppm -v 2>&1 | head -1))${NC}"
else
    echo -e "${YELLOW}未安装${NC}"
    MISSING+=("pdftoppm")
fi

# ============================================================
# 3. 检测/安装 tesseract
# ============================================================
echo -n "🔍 tesseract ... "
if command -v tesseract &>/dev/null; then
    echo -e "${GREEN}已安装 ($(tesseract --version 2>&1 | head -1))${NC}"
else
    echo -e "${YELLOW}未安装${NC}"
    MISSING+=("tesseract")
fi

# ============================================================
# 4. 检测 LibreOffice (macOS 专属路径查找)
# ============================================================
echo -n "🔍 LibreOffice ... "
# 常见安装路径
LO_PATHS=(
    "/Applications/LibreOffice.app"
    "$HOME/Applications/LibreOffice.app"
)
# mdfind (macOS Spotlight)
if command -v mdfind &>/dev/null; then
    LO_MDFIND=$(mdfind -name "soffice" 2>/dev/null | grep -m1 "LibreOffice.*soffice$" || true)
    if [ -n "$LO_MDFIND" ]; then
        LO_MDFIND_DIR=$(dirname "$(dirname "$(dirname "$LO_MDFIND")")")
        LO_PATHS+=("$LO_MDFIND_DIR")
    fi
fi

for p in "${LO_PATHS[@]}"; do
    if [ -f "$p/Contents/MacOS/soffice" ]; then
        FOUND_LIBREOFFICE="$p"
        echo -e "${GREEN}$p${NC}"
        break
    fi
done

if [ -z "$FOUND_LIBREOFFICE" ]; then
    echo -e "${YELLOW}未找到${NC}"
    MISSING+=("libreoffice")
fi

# ============================================================
# 5. 检测 Python + pdfplumber
# ============================================================
echo -n "🔍 Python (pdfplumber) ... "

detect_pdfplumber_python() {
    # 搜索顺序: 显式标记的环境变量 > conda > pyenv > venv > 系统
    local candidates=()

    # 5a. 环境变量
    [ -n "$PDFPLUMBER_PYTHON" ] && candidates+=("$PDFPLUMBER_PYTHON")

    # 5b. 常见 conda 路径
    for conda_base in "$HOME/miniconda3" "$HOME/anaconda3" "/opt/miniconda3" "/opt/anaconda3"; do
        [ -f "$conda_base/bin/python" ] && candidates+=("$conda_base/bin/python")
    done

    # 5c. pyenv
    if command -v pyenv &>/dev/null; then
        for ver in $(pyenv versions --bare 2>/dev/null | head -3); do
            local py_path
            py_path="$(pyenv root)/versions/$ver/bin/python"
            [ -f "$py_path" ] && candidates+=("$py_path")
        done
    fi

    # 5d. 系统 python3
    command -v python3 &>/dev/null && candidates+=("$(command -v python3)")
    command -v python &>/dev/null && candidates+=("$(command -v python)")

    # 逐个测试
    for py in "${candidates[@]}"; do
        [ -z "$py" ] && continue
        if "$py" -c "import pdfplumber" 2>/dev/null; then
            echo "$py"
            return 0
        fi
    done
    return 1
}

FOUND_PDFPLUMBER_PYTHON=$(detect_pdfplumber_python)
if [ -n "$FOUND_PDFPLUMBER_PYTHON" ]; then
    echo -e "${GREEN}$FOUND_PDFPLUMBER_PYTHON${NC}"
else
    echo -e "${YELLOW}未找到${NC}"
    MISSING+=("pdfplumber")
fi

# ============================================================
# 6. 检测 python-pptx
# ============================================================
echo -n "🔍 python-pptx ... "
PYPPTX_PYTHON=""
for py in "$FOUND_PDFPLUMBER_PYTHON" "$(command -v python3)" "$(command -v python)"; do
    [ -z "$py" ] && continue
    if "$py" -c "import pptx" 2>/dev/null; then
        PYPPTX_PYTHON="$py"
        echo -e "${GREEN}可用 ($py)${NC}"
        break
    fi
done
if [ -z "$PYPPTX_PYTHON" ]; then
    echo -e "${YELLOW}未安装${NC}"
fi

# ============================================================
# 7. 安装缺失的依赖
# ============================================================

if [ ${#MISSING[@]} -gt 0 ]; then
    echo ""
    echo -e "${YELLOW}----------------------------------------${NC}"
    echo -e "${YELLOW}  缺失依赖: ${MISSING[*]}${NC}"
    echo -e "${YELLOW}----------------------------------------${NC}"
    echo ""

    # 安装确认
    read -p "是否自动安装缺失依赖? [Y/n] " -r REPLY
    REPLY=${REPLY:-Y}
    if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
        echo "已跳过安装，请手动安装后重新运行 setup.sh"
        exit 1
    fi

    for dep in "${MISSING[@]}"; do
        case "$dep" in
            pdftoppm)
                echo ""
                echo -e "${CYAN}📥 安装 pdftoppm (poppler)...${NC}"
                case "$PKG_MANAGER" in
                    brew) brew install poppler ;;
                    apt)  sudo apt-get install -y poppler-utils ;;
                    dnf)  sudo dnf install -y poppler-utils ;;
                    *) echo -e "${RED}请手动安装 poppler-utils${NC}" ;;
                esac
                ;;
            tesseract)
                echo ""
                echo -e "${CYAN}📥 安装 tesseract...${NC}"
                case "$PKG_MANAGER" in
                    brew)
                        brew install tesseract
                        brew install tesseract-lang  # 中文/英文语言包
                        ;;
                    apt)
                        sudo apt-get install -y tesseract-ocr tesseract-ocr-chi-sim tesseract-ocr-eng
                        ;;
                    dnf)
                        sudo dnf install -y tesseract tesseract-langpack-chi_sim tesseract-langpack-eng
                        ;;
                    *) echo -e "${RED}请手动安装 tesseract${NC}" ;;
                esac
                ;;
            libreoffice)
                echo ""
                echo -e "${CYAN}📥 安装 LibreOffice...${NC}"
                case "$PKG_MANAGER" in
                    brew) brew install --cask libreoffice ;;
                    apt)  sudo apt-get install -y libreoffice ;;
                    dnf)  sudo dnf install -y libreoffice ;;
                    *)
                        echo -e "${YELLOW}请手动下载安装 LibreOffice:${NC}"
                        echo "  https://www.libreoffice.org/download/"
                        ;;
                esac
                # 重检测
                echo -n "🔍 重新检测 LibreOffice ... "
                for p in "/Applications/LibreOffice.app" "$HOME/Applications/LibreOffice.app"; do
                    if [ -f "$p/Contents/MacOS/soffice" ]; then
                        FOUND_LIBREOFFICE="$p"
                        echo -e "${GREEN}$p${NC}"
                        break
                    fi
                done
                ;;
            pdfplumber)
                echo ""
                echo -e "${CYAN}📥 安装 pdfplumber (Python 包)...${NC}"

                # 找一个可用的 Python
                INSTALL_PY=""
                for py in "$(command -v python3)" "$(command -v python)"; do
                    [ -z "$py" ] && continue
                    INSTALL_PY="$py"
                    break
                done

                if [ -z "$INSTALL_PY" ]; then
                    echo -e "${RED}未找到可用的 Python，请先安装 Python 3.9+${NC}"
                    exit 1
                fi

                echo "  使用 Python: $INSTALL_PY"
                "$INSTALL_PY" -m pip install pdfplumber

                # 如果系统 Python 权限不足，尝试 --user
                if [ $? -ne 0 ]; then
                    echo -e "${YELLOW}  权限不足，尝试 --user 安装...${NC}"
                    "$INSTALL_PY" -m pip install --user pdfplumber
                fi

                # 重检测
                FOUND_PDFPLUMBER_PYTHON="$INSTALL_PY"
                ;;
        esac
    done

    echo ""
    echo -e "${GREEN}✅ 所有依赖安装完成${NC}"
fi

# ============================================================
# 8. 生成 config.sh
# ============================================================

echo ""
echo -e "${CYAN}📝 生成 config.sh ...${NC}"

cat > "$CONFIG_FILE" << EOF
# ============================================================
# ppt-extract 本机环境配置 (自动生成于 $(date '+%Y-%m-%d %H:%M'))
# 由 setup.sh 生成，按需修改
# ============================================================

# LibreOffice 安装路径
LIBREOFFICE_PATH="${FOUND_LIBREOFFICE:-/Applications/LibreOffice.app}"

# 安装了 pdfplumber 的 Python 解释器
PDFPLUMBER_PYTHON="${FOUND_PDFPLUMBER_PYTHON:-python3}"
EOF

echo -e "${GREEN}✅ config.sh 已生成${NC}"
echo ""
echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}  环境就绪${NC}"
echo -e "${CYAN}============================================${NC}"
echo ""
echo "  LibreOffice:   ${FOUND_LIBREOFFICE:-⚠️  未找到 (仅 PPTX 输入需要)}"
echo "  pdfplumber:    ${FOUND_PDFPLUMBER_PYTHON:-⚠️  未找到 (仅 PDF 输入需要)}"
echo "  pdftoppm:      $(command -v pdftoppm || echo '⚠️  未安装')"
echo "  tesseract:     $(command -v tesseract || echo '⚠️  未安装')"
echo "  config:        $CONFIG_FILE"
echo ""
