#!/bin/bash
# ============================================================
#  deploy.sh — 一键更新并部署源到 GitHub Pages
#  用法: bash scripts/deploy.sh
# ============================================================

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

# 自动检测 git 远程名
ORIGIN="$(git remote 2>/dev/null | head -1)"
if [ -z "$ORIGIN" ]; then
    echo "[错误] 没有找到 git 远程仓库"
    exit 1
fi

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
CHANGES="$(git status --porcelain 2>/dev/null)"
if [ -z "$CHANGES" ]; then
    echo "[提示] 没有需要提交的更改"
else
    # 尝试 git add，如果权限不足则使用 sudo
    if ! git add -A 2>/dev/null; then
        echo "       (权限不足，使用 sudo)"
        echo "q" | sudo -S git add -A
    fi
    if git commit -m "repo: $(date '+%Y-%m-%d %H:%M') 更新" 2>/dev/null; then
        echo "[完成] 已提交"
    else
        echo "       (权限不足，使用 sudo)"
        echo "q" | sudo -S git commit -m "repo: $(date '+%Y-%m-%d %H:%M') 更新"
        echo "[完成] 已提交"
    fi
fi

# 4. Git 推送
echo ""
echo "========================================="
echo "  步骤 3/3: 推送到 GitHub"
echo "========================================="
if git push "$ORIGIN" main 2>/dev/null; then
    :
else
    echo "       (权限不足，使用 sudo)"
    echo "q" | sudo -S git push "$ORIGIN" main
fi
echo "[完成] 已推送，GitHub Pages 稍后自动更新"

echo ""
echo "========================================="
echo "  ✅ 部署完成"
echo "========================================="
