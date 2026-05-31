#!/bin/bash
#===============================================================
# Sileo Repo Auto-Update Script
# 扫描 debs/ 目录 → 生成 Packages / Release
#===============================================================

set -e

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEBS_DIR="$ROOT_DIR/debs"

# 检查 dpkg-scanpackages 是否存在
if ! command -v dpkg-scanpackages &>/dev/null; then
    echo "[ERROR] dpkg-scanpackages not found. Install dpkg-dev first:"
    echo "        apt install dpkg-dev"
    exit 1
fi

echo "========================================"
echo " Sileo Repo Update"
echo "========================================"
echo "Root: $ROOT_DIR"
echo ""

# 1. 扫描 debs 生成 Packages
echo "[1/4] Generating Packages..."
cd "$ROOT_DIR"
dpkg-scanpackages --arch all debs/ > Packages 2>/dev/null || {
    dpkg-scanpackages debs/ > Packages 2>/dev/null || {
        echo "[ERROR] dpkg-scanpackages failed. Check debs/ directory."
        exit 1
    }
}
echo "       Packages generated."

# 2. 多格式压缩
echo "[2/4] Compressing Packages..."
bzip2 -fzk Packages   # Packages.bz2
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
Origin: sxllm
Label: sxllm Repo
Suite: stable
Version: 1.0
Codename: ios
Architectures: iphoneos-arm iphoneos-arm64 iphoneos-arm64e
Components: main
Description: sxllm's Sileo package repository
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
echo "      https://sxllm.github.io/sileo-repo/"
echo ""
