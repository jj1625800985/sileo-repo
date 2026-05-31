#!/bin/bash
#===============================================================
# Sileo Repo Auto-Update Script
# 扫描 debs/ 目录 → 生成 Packages / Release
# 支持 zstd 压缩的 .deb（如 Theos 构建的包）
#===============================================================

set -e

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEBS_DIR="$ROOT_DIR/debs"

echo "========================================"
echo " Sileo Repo Update"
echo "========================================"
echo "Root: $ROOT_DIR"
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
                *.zst) CTRL_DATA=$(ar p "$deb" "$ctrl" 2>/dev/null | tar --zstd -xO ./control 2>/dev/null) ;;
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
                REPO_URL="https://jj1625800985.github.io/sileo-repo"
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

# 2-4 不变
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
SHA512SUM=$(sha512sum Packages 2>/dev/null | cut -d' ' -f1)

# 4. 生成 Release 文件
echo "[4/4] Writing Release file..."
cat > Release <<EOF
Origin: jj1625800985
Label: jj1625800985 Repo
Suite: stable
Version: 1.0
Codename: ios
Architectures: iphoneos-arm iphoneos-arm64 iphoneos-arm64e
Components: main
Description: jj1625800985's Sileo package repository
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
echo "Next steps:"
echo "   1. Add .deb files to debs/"
echo "   2. Run ./update.sh"
echo "   3. Commit & push to GitHub"
echo "   4. Enable GitHub Pages (main branch, /root)"
echo "   5. Add source in Sileo:"
echo "      https://jj1625800985.github.io/sileo-repo/"
echo ""
