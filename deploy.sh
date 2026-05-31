#!/bin/bash
#===============================================================
# 一键部署脚本
# 更新仓库 → Git 提交 → Git 推送
#===============================================================
set -e

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

# 从 repo.conf 加载 REPO_URL
REPO_CONFIG="$ROOT_DIR/repo.conf"
REPO_URL="https://jj1625800985.github.io/sileo-repo"
if [ -f "$REPO_CONFIG" ]; then
    source "$REPO_CONFIG"
fi

echo ""
echo "========================================"
echo " 🚀 sxllm Repo - 一键部署"
echo "========================================"
echo ""

# 1. 检查是否有 deb
DEB_COUNT=$(ls debs/*.deb 2>/dev/null | wc -l)
if [ "$DEB_COUNT" -eq 0 ]; then
    echo "[!] debs/ 目录下没有 .deb 文件"
    echo "    先将 .deb 放入 debs/ 目录再运行"
    echo ""
    exit 1
fi
echo "[1/5] 检测到 $DEB_COUNT 个 .deb 包"
echo ""

# 2. 运行 update.sh
echo "[2/5] 更新仓库索引..."
if [ -f "$ROOT_DIR/scripts/update.sh" ]; then
    bash "$ROOT_DIR/scripts/update.sh"
else
    echo "[ERROR] update.sh 不存在"
    exit 1
fi
echo ""

# 3. Git 安全目录豁免（防止 dubious ownership 报错）
echo "[3/5] Git 安全目录配置..."
if git config --global --add safe.directory "$ROOT_DIR" 2>/dev/null; then
    echo "    [✓] Git 安全目录已配置"
else
    echo "    [!] Git 安全目录配置失败（可能已存在）"
fi
echo ""

# 4. Git 提交
echo "[4/5] Git 提交..."
TIMESTAMP=$(date "+%Y-%m-%d %H:%M")
DEB_NAMES=$(ls debs/*.deb 2>/dev/null | xargs -n1 basename | tr '\n' ' ')
export TMPDIR=/var/tmp
git add -A
git commit -m "📦 update: $DEB_COUNT packages ($TIMESTAMP)

$DEB_NAMES"
echo ""

# 5. Git 推送
echo "[5/5] Git 推送到 GitHub..."
if git push; then
    echo ""
    echo "========================================"
    echo " ✅ 部署完成！"
    echo "========================================"
    echo ""
    echo "   源地址: $REPO_URL/"
    echo "   等待 GitHub Pages 更新 (约1-2分钟)"
    echo ""
else
    echo "[ERROR] 推送失败，请检查网络或 Git 配置"
    exit 1
fi
