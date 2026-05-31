#!/bin/bash
#===============================================================
# Sileo Repo Auto-Update Script
# 扫描 debs/ 目录 → 生成 Packages / Release
# 支持 zstd 压缩的 .deb（如 Theos 构建的包）
#
# 用法:
#   ./scripts/update.sh              # 使用现有配置更新
#   ./scripts/update.sh -i           # 交互式配置 + 更新
#   ./scripts/update.sh --interactive
#   ./scripts/update.sh --config     # 仅交互式配置，不更新
#===============================================================

set -e

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEBS_DIR="$ROOT_DIR/debs"
REPO_CONFIG="$ROOT_DIR/repo.conf"

# 切换到仓库根目录，确保所有相对路径操作正确
cd "$ROOT_DIR"
INTERACTIVE_MODE=false
CONFIG_ONLY=false

# ---- 解析命令行参数 ----
for arg in "$@"; do
    case "$arg" in
        -i|--interactive) INTERACTIVE_MODE=true ;;
        --config)         INTERACTIVE_MODE=true; CONFIG_ONLY=true ;;
    esac
done

# ---- 默认配置 ----
DEFAULT_ORIGIN="jj1625800985"
DEFAULT_LABEL="jj1625800985 Repo"
DEFAULT_DESCRIPTION="jj1625800985's Sileo package repository"
DEFAULT_REPO_URL="https://jj1625800985.github.io/sileo-repo"

# ---- 加载配置文件 ----
load_config() {
    if [ -f "$REPO_CONFIG" ]; then
        source "$REPO_CONFIG"
        echo "[✓] 已加载配置: $REPO_CONFIG"
    else
        ORIGIN="$DEFAULT_ORIGIN"
        LABEL="$DEFAULT_LABEL"
        DESCRIPTION="$DEFAULT_DESCRIPTION"
        REPO_URL="$DEFAULT_REPO_URL"
        echo "[!] 未找到配置文件，使用默认值"
    fi
}

# ---- 保存配置文件 ----
save_config() {
    cat > "$REPO_CONFIG" <<EOF
# Sileo Repo 配置
# 可通过 ./scripts/update.sh --config 交互式修改
ORIGIN="$ORIGIN"
LABEL="$LABEL"
DESCRIPTION="$DESCRIPTION"
REPO_URL="$REPO_URL"
EOF
    echo "[✓] 配置已保存: $REPO_CONFIG"
}

# ---- 交互式配置 ----
interactive_config() {
    echo ""
    echo "========================================"
    echo "  仓库信息配置"
    echo "  留空则保持当前值不变"
    echo "========================================"
    echo ""

    read -r -p "Origin  [$ORIGIN]: " input
    ORIGIN="${input:-$ORIGIN}"

    read -r -p "Label   [$LABEL]: " input
    LABEL="${input:-$LABEL}"

    echo "Description (当前: $DESCRIPTION)"
    read -r -p "  新描述: " input
    DESCRIPTION="${input:-$DESCRIPTION}"

    read -r -p "Repo URL [$REPO_URL]: " input
    REPO_URL="${input:-$REPO_URL}"

    echo ""
    echo "========================================"
    echo "  配置预览"
    echo "========================================"
    echo "  Origin:      $ORIGIN"
    echo "  Label:       $LABEL"
    echo "  Description: $DESCRIPTION"
    echo "  Repo URL:    $REPO_URL"
    echo "========================================"
    echo ""
    read -r -p "确认保存？(Y/n): " confirm
    case "$confirm" in
        n|N|no|NO) echo "已取消"; exit 0 ;;
        *) save_config ;;
    esac
}

# ---- 主流程开始 ----
echo "========================================"
echo " Sileo Repo Update"
echo "========================================"
echo "Root: $ROOT_DIR"
echo ""

# 加载现有配置
load_config

# 如果是 --config 模式，只配置不更新
if [ "$CONFIG_ONLY" = true ]; then
    interactive_config
    exit 0
fi

# 如果没有配置文件，或指定了 -i，进入交互模式
if [ ! -f "$REPO_CONFIG" ] || [ "$INTERACTIVE_MODE" = true ]; then
    interactive_config
fi

# 检查 debs 目录
DEB_COUNT=$(ls "$DEBS_DIR"/*.deb 2>/dev/null | wc -l)
if [ "$DEB_COUNT" -eq 0 ]; then
    echo "[!] debs/ 目录下没有 .deb 文件"
    echo "    请先将 .deb 放入 debs/ 目录"
    echo ""
    exit 1
fi
echo "[0/4] 检测到 $DEB_COUNT 个 .deb 包"
echo ""

# 清理可能存在的 root 权限旧文件
rm -f Packages Packages.bz2 Packages.gz Packages.xz Packages.lzma Packages.zst Release 2>/dev/null || true

# 1. 扫描 debs 生成 Packages
echo "[1/4] Generating Packages..."

# 先尝试 dpkg-scanpackages（标准 .deb）
GENERATED=false
if command -v dpkg-scanpackages &>/dev/null; then
    if dpkg-scanpackages debs/ > Packages 2>/dev/null; then
        GENERATED=true
    fi
fi

# 如果 dpkg-scanpackages 失败，手动提取（支持 zstd 格式的 .deb）
if [ "$GENERATED" = false ]; then
    echo "       (dpkg-scanpackages 不兼容，手动提取控制信息...)"
    > Packages
    for deb in "$DEBS_DIR"/*.deb; do
        [ -f "$deb" ] || continue
        # 探测 control 压缩格式
        set +e
        for ctrl in control.tar.zst control.tar.gz control.tar.xz control.tar; do
            CTRL_DATA=""
            case "$ctrl" in
                *.zst) CTRL_DATA=$(ar p "$deb" "$ctrl" 2>/dev/null | zstd -d 2>/dev/null | tar xO ./control 2>/dev/null) ;;
                *.gz)  CTRL_DATA=$(ar p "$deb" "$ctrl" 2>/dev/null | tar xzO ./control 2>/dev/null) ;;
                *.xz)  CTRL_DATA=$(ar p "$deb" "$ctrl" 2>/dev/null | tar xJO ./control 2>/dev/null) ;;
                *)     CTRL_DATA=$(ar p "$deb" "$ctrl" 2>/dev/null | tar xO ./control 2>/dev/null) ;;
            esac
            if [ -n "$CTRL_DATA" ]; then
                DEBFILE=$(basename "$deb")
                SIZE=$(wc -c < "$deb")
                MD5=$(md5sum "$deb" | cut -d' ' -f1)
                SHA1=$(sha1sum "$deb" | cut -d' ' -f1)
                SHA256=$(sha256sum "$deb" | cut -d' ' -f1)
                # 提取包ID用于生成本地 URLs
                PKG_ID=$(echo "$CTRL_DATA" | grep -i "^Package:" | head -1 | cut -d' ' -f2)
                # 重写 Sileodepiction 和 Icon 指向本地仓库
                echo "$CTRL_DATA" | sed \
                    -e "s|^Sileodepiction:.*|Sileodepiction: $REPO_URL/depictions/$PKG_ID/info.json|" \
                    -e "s|^Icon:.*|Icon: $REPO_URL/icon/$PKG_ID.png|"
                echo "Filename: ./debs/$DEBFILE"
                echo "Size: $SIZE"
                echo "MD5sum: $MD5"
                echo "SHA1: $SHA1"
                echo "SHA256: $SHA256"
                echo ""
                break
            fi
        done
        set -e
    done >> Packages
fi

echo "       Packages generated."

# 2. 压缩 Packages
echo "[2/4] Compressing Packages..."
bzip2 -fzk Packages
gzip  -fk Packages    # Packages.gz
xz    -fzk Packages   # Packages.xz  (Sileo 推荐)
command -v lzma &>/dev/null && lzma -fzk Packages || echo "       (lzma not installed, skipped)"
command -v zstd &>/dev/null && zstd -fk Packages || echo "       (zstd not installed, skipped)"
echo "       bz2 gz xz lzma zst done."

# 3. 计算校验和
echo "[3/4] Calculating checksums..."
PACKAGES_SIZE=$(wc -c < Packages 2>/dev/null || echo 0)

MD5SUM=$(md5sum Packages 2>/dev/null | cut -d' ' -f1 || md5 Packages 2>/dev/null | cut -d'=' -f2 | tr -d ' ')
SHA1SUM=$(sha1sum Packages 2>/dev/null | cut -d' ' -f1)
SHA256SUM=$(sha256sum Packages 2>/dev/null | cut -d' ' -f1)

# 4. 生成 Release 文件（使用配置中的值）
echo "[4/4] Writing Release file..."
cat > Release <<EOF
Origin: $ORIGIN
Label: $LABEL
Suite: stable
Version: 1.0
Codename: ios
Architectures: iphoneos-arm iphoneos-arm64 iphoneos-arm64e
Components: main
Description: $DESCRIPTION
Date: $(date -R)
EOF

# 添加校验和
{
    echo ""
    echo "MD5Sum:"
    echo " $MD5SUM $PACKAGES_SIZE Packages"
    if [ -f Packages.bz2 ]; then
        echo " $(md5sum Packages.bz2 | cut -d' ' -f1) $(wc -c < Packages.bz2) Packages.bz2"
    fi
    if [ -f Packages.gz ]; then
        echo " $(md5sum Packages.gz | cut -d' ' -f1) $(wc -c < Packages.gz) Packages.gz"
    fi
    if [ -f Packages.xz ]; then
        echo " $(md5sum Packages.xz | cut -d' ' -f1) $(wc -c < Packages.xz) Packages.xz"
    fi
    if [ -f Packages.lzma ]; then
        echo " $(md5sum Packages.lzma | cut -d' ' -f1) $(wc -c < Packages.lzma) Packages.lzma"
    fi
    if [ -f Packages.zst ]; then
        echo " $(md5sum Packages.zst | cut -d' ' -f1) $(wc -c < Packages.zst) Packages.zst"
    fi

    echo ""
    echo "SHA1:"
    echo " $SHA1SUM $PACKAGES_SIZE Packages"
    if [ -f Packages.bz2 ]; then
        echo " $(sha1sum Packages.bz2 | cut -d' ' -f1) $(wc -c < Packages.bz2) Packages.bz2"
    fi
    if [ -f Packages.gz ]; then
        echo " $(sha1sum Packages.gz | cut -d' ' -f1) $(wc -c < Packages.gz) Packages.gz"
    fi
    if [ -f Packages.xz ]; then
        echo " $(sha1sum Packages.xz | cut -d' ' -f1) $(wc -c < Packages.xz) Packages.xz"
    fi
    if [ -f Packages.lzma ]; then
        echo " $(sha1sum Packages.lzma | cut -d' ' -f1) $(wc -c < Packages.lzma) Packages.lzma"
    fi
    if [ -f Packages.zst ]; then
        echo " $(sha1sum Packages.zst | cut -d' ' -f1) $(wc -c < Packages.zst) Packages.zst"
    fi

    echo ""
    echo "SHA256:"
    echo " $SHA256SUM $PACKAGES_SIZE Packages"
    if [ -f Packages.bz2 ]; then
        echo " $(sha256sum Packages.bz2 | cut -d' ' -f1) $(wc -c < Packages.bz2) Packages.bz2"
    fi
    if [ -f Packages.gz ]; then
        echo " $(sha256sum Packages.gz | cut -d' ' -f1) $(wc -c < Packages.gz) Packages.gz"
    fi
    if [ -f Packages.xz ]; then
        echo " $(sha256sum Packages.xz | cut -d' ' -f1) $(wc -c < Packages.xz) Packages.xz"
    fi
    if [ -f Packages.lzma ]; then
        echo " $(sha256sum Packages.lzma | cut -d' ' -f1) $(wc -c < Packages.lzma) Packages.lzma"
    fi
    if [ -f Packages.zst ]; then
        echo " $(sha256sum Packages.zst | cut -d' ' -f1) $(wc -c < Packages.zst) Packages.zst"
    fi
} >> Release

echo ""
echo "========================================"
echo " Done! Repo ready at:"
echo "   $ROOT_DIR"
echo "========================================"
echo ""
echo "Current Sileo display:"
echo "  源名称:  $LABEL"
echo "  描述:    $DESCRIPTION"
echo "  地址:    $REPO_URL"
echo ""
echo "Next steps:"
echo "   1. Add .deb files to debs/"
echo "   2. Run ./scripts/update.sh"
echo "   3. Commit & push to GitHub"
echo "   4. Enable GitHub Pages (main branch, /root)"
echo "   5. Add source in Sileo:"
echo "      $REPO_URL"
echo ""
