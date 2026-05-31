#!/bin/bash
# ============================================================
#  deploy.sh — 一键更新并部署源到 GitHub Pages
#  用法: bash scripts/deploy.sh
# ============================================================

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

# 1. 检查 repo.conf
if [ ! -f repo.conf ]; then
    echo "[错误] repo.conf 不存在，请先运行: bash scripts/update.sh -i"
    exit 1
fi
source repo.conf

ORIGIN="${ORIGIN:-origin}"

# 2. 运行 update.sh
echo "========================================="
echo "  步骤 1/3: 更新 Packages / Release / Depictions"
echo "========================================="
bash scripts/update.sh || {
    echo "[错误] update.sh 执行失败"
    exit 1
}

# 3. Git 提交
echo ""
echo "========================================="
echo "  步骤 2/3: 提交更改到 Git"
echo "========================================="

# 检查是否有变更
if [ -z "$(git status --porcelain)" ]; then
    echo "[提示] 没有需要提交的更改"
else
    git add -A
    git commit -m "repo: $(date '+%Y-%m-%d %H:%M') 更新"
    echo "[完成] 已提交"
fi

# 4. Git 推送
echo ""
echo "========================================="
echo "  步骤 3/3: 推送到 GitHub"
echo "========================================="
git push "$ORIGIN" main
echo "[完成] 已推送，GitHub Pages 稍后自动更新"

echo ""
echo "========================================="
echo "  ✅ 部署完成"
echo "========================================="
