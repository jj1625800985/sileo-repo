#!/bin/bash
# ============================================================
#  deploy.sh — 一键更新并部署源到 GitHub Pages
#  用法: bash scripts/deploy.sh
# ============================================================

export LC_ALL=C
export DEPLOY_MODE=1

# ---- 颜色定义 ----
C_RESET="\033[0m"; C_BOLD="\033[1m"; C_DIM="\033[2m"
C_RED="\033[0;31m"; C_GREEN="\033[0;32m"; C_YELLOW="\033[0;33m"
C_BLUE="\033[0;34m"; C_PURPLE="\033[1;35m"; C_CYAN="\033[1;36m"
C_GRAY="\033[0;90m"
cecho() { local c="$1"; shift; echo -e "${c}$*${C_RESET}"; }

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

# 自动检测 git 远程名（多层 fallback）
REMOTE="$(git remote 2>/dev/null | head -1)"
if [ -z "$REMOTE" ]; then
    cecho "$C_YELLOW" "[!] git remote 检测失败，尝试读取 .git/config..."
    # fallback 1: 直接从 .git/config 读取
    if [ -f ".git/config" ]; then
        REMOTE=$(grep '^\[remote "' .git/config 2>/dev/null | head -1 | sed 's/\[remote "//;s/"\]//')
    fi
    # fallback 2: 使用 origin 作为默认
    if [ -z "$REMOTE" ]; then
        cecho "$C_YELLOW" "[!] 无法检测远程名，使用默认: origin"
        REMOTE="origin"
    else
        cecho "$C_GREEN" "[i] 已从 .git/config 读取远程名: $REMOTE"
    fi
fi

# 2. 运行 update.sh
echo ""
cecho "$C_CYAN" "╔═══════════════════════════════════════════╗"
cecho "$C_CYAN" "║  步骤 1/3: 更新 Packages / Release / Depictions  ║"
cecho "$C_CYAN" "╚═══════════════════════════════════════════╝"
bash scripts/update.sh || {
    cecho "$C_RED" "[错误] update.sh 执行失败"
    exit 1
}

# 3. Git 提交
echo ""
cecho "$C_CYAN" "╔═══════════════════════════════════════════╗"
cecho "$C_CYAN" "║  步骤 2/3: 提交更改到 Git                ║"
cecho "$C_CYAN" "╚═══════════════════════════════════════════╝"

# 检查是否有变更
CHANGES="$(git status --porcelain 2>/dev/null)"
if [ -z "$CHANGES" ]; then
    cecho "$C_YELLOW" "[提示] 没有需要提交的更改"
else
    # 统计包数量用于 commit 信息
    PKG_COUNT=$(ls debs/*.deb 2>/dev/null | wc -l | tr -d ' ')
    COMMIT_MSG="📦 update: $PKG_COUNT packages ($(date '+%Y-%m-%d %H:%M'))"
    echo -e "  ${C_DIM}提交信息:${C_RESET} $COMMIT_MSG"

    if ! git add -A 2>/dev/null; then
        echo -e "  ${C_YELLOW}权限不足，使用 sudo${C_RESET}"
        echo "q" | sudo -S git add -A
    fi
    if git commit -m "$COMMIT_MSG" 2>/dev/null; then
        cecho "$C_GREEN" "  [✓] 已提交"
    else
        echo -e "  ${C_YELLOW}权限不足，使用 sudo${C_RESET}"
        echo "q" | sudo -S git commit -m "$COMMIT_MSG"
        cecho "$C_GREEN" "  [✓] 已提交"
    fi
fi

# 4. Git 推送
echo ""
cecho "$C_CYAN" "╔═══════════════════════════════════════════╗"
cecho "$C_CYAN" "║  步骤 3/3: 推送到 GitHub                 ║"
cecho "$C_CYAN" "╚═══════════════════════════════════════════╝"
if git push "$REMOTE" main 2>/dev/null; then
    :
else
    echo -e "  ${C_YELLOW}权限不足，使用 sudo${C_RESET}"
    echo "q" | sudo -S git push "$REMOTE" main
fi
cecho "$C_GREEN" "  [✓] 已推送，GitHub Pages 稍后自动更新"

echo ""
cecho "$C_CYAN" "╔═══════════════════════════════════════════╗"
cecho "$C_CYAN" "║           部署完成！                      ║"
cecho "$C_CYAN" "╚═══════════════════════════════════════════╝"
