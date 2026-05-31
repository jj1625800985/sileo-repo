#!/bin/bash
#===============================================================
# 插件展示信息编辑工具
# 用法: ./editpkg.sh <包ID 或 .deb文件>
# 示例: ./editpkg.sh com.Axs.stheno
#       ./editpkg.sh debs/xxx.deb
#===============================================================
set -e

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_URL="https://jj1625800985.github.io/sileo-repo"

if [ -z "$1" ]; then
    echo "用法: ./editpkg.sh <包ID 或 .deb文件>"
    echo "  例: ./editpkg.sh com.Axs.stheno"
    echo "  例: ./editpkg.sh debs/xxx.deb"
    echo ""
    echo "已有包:"
    if [ -d "$ROOT_DIR/depictions/" ]; then
        ls "$ROOT_DIR/depictions/"
    else
        echo "  (无)"
    fi
    echo ""
    echo "debs/ 目录:"
    if ls "$ROOT_DIR/debs/"*.deb >/dev/null 2>&1; then
        ls "$ROOT_DIR/debs/"*.deb 2>/dev/null
    else
        echo "  (无)"
    fi
    exit 1
fi

INPUT="$1"

if [[ "$INPUT" == *.deb ]]; then
    if [ ! -f "$INPUT" ]; then
        echo "文件不存在: $INPUT"
        exit 1
    fi
    if [[ "$INPUT" != "$ROOT_DIR/debs/"* ]]; then
        cp "$INPUT" "$ROOT_DIR/debs/"
        echo "已复制到 debs/"
    fi
    echo "读取包名..."
    PKG_ID=""
    for ctrl in control.tar.zst control.tar.gz control.tar.xz control.tar; do
        if ar p "$INPUT" "$ctrl" >/tmp/pkgctl 2>/dev/null; then
            EXTRACTED=$(tar --zstd -xO ./control </tmp/pkgctl 2>/dev/null || \
                        tar xzO ./control </tmp/pkgctl 2>/dev/null || \
                        tar xJO ./control </tmp/pkgctl 2>/dev/null || \
                        tar xO ./control </tmp/pkgctl 2>/dev/null)
            if [ -n "$EXTRACTED" ]; then
                PKG_ID=$(echo "$EXTRACTED" | grep "^Package:" | sed 's/Package: *//')
                break
            fi
        fi
    done
    rm -f /tmp/pkgctl
    if [ -z "$PKG_ID" ]; then
        echo "无法解析 .deb"
        exit 1
    fi
    echo "包名: $PKG_ID"
else
    PKG_ID="$INPUT"
fi

DEP_DIR="$ROOT_DIR/depictions/$PKG_ID"
SCREENSHOT_DIR="$DEP_DIR/screenshots"
ICON_DIR="$ROOT_DIR/icon"

if [ ! -d "$DEP_DIR" ]; then
    echo "新建插件: $PKG_ID"
    mkdir -p "$SCREENSHOT_DIR"
fi

echo ""
echo "==== 填写插件信息 (直接回车保持不变) ===="

if [ -f "$DEP_DIR/info.json" ]; then
    CURRENT_NAME=$(grep '"title"' "$DEP_DIR/info.json" | head -1 | sed 's/.*"title": "\(.*\)",/\1/')
    CURRENT_DESC=$(grep '"subheader"' "$DEP_DIR/info.json" | head -1 | sed 's/.*"title": "\(.*\)"/\1/')
    CURRENT_TEXT=$(grep -A5 '"DepictionTextView"' "$DEP_DIR/info.json" | grep '"text"' | head -1 | sed 's/.*"text": "\(.*\)"/\1/' | sed 's/\\n/\
/g')
else
    CURRENT_NAME=""
    CURRENT_DESC=""
    CURRENT_TEXT=""
fi

read -p "插件名称 [$CURRENT_NAME]: " NAME
NAME="${NAME:-$CURRENT_NAME}"
[ -z "$NAME" ] && echo "插件名不能为空" && exit 1

read -p "插件简介 [$CURRENT_DESC]: " DESC
DESC="${DESC:-$CURRENT_DESC}"

echo "详细说明 (输入 . 结束):"
if [ -n "$CURRENT_TEXT" ]; then
    echo "当前:"
    echo "$CURRENT_TEXT"
fi
TEXT=""
while IFS= read -r line; do
    [ "$line" = "." ] && break
    [ -z "$TEXT" ] && TEXT="$line" || TEXT="$TEXT
$line"
done
TEXT="${TEXT:-$CURRENT_TEXT}"

# 生成 info.json
{
echo "{"
echo '  "minVersion": "16.0",'
echo '  "class": "DepictionTabView",'
echo '  "headerImage": "'$REPO_URL/icon/$PKG_ID.png'",'
echo '  "tintColor": "#4A90D9",'
echo '  "tabs": ['
echo '    {'
echo '      "tabname": "详情",'
echo '      "class": "DepictionStackView",'
echo '      "views": ['
echo '        {"class": "DepictionHeaderView", "title": "'$NAME'", "useBoldText": true},'
echo '        {"class": "DepictionSubheaderView", "title": "'$DESC'"},'
echo '        {"class": "DepictionSpacerView", "spacing": 8},'
echo '        {"class": "DepictionSeparatorView"},'
echo '        {"class": "DepictionHeaderView", "title": "说明"},'
echo '        {"class": "DepictionTextView", "text": "'$TEXT'"},'
echo '        {"class": "DepictionSpacerView", "spacing": 8},'
echo '        {"class": "DepictionSeparatorView"},'
echo '        {"class": "DepictionHeaderView", "title": "截图"},'
echo '        {'
echo '          "class": "DepictionScreenshotsView",'
echo '          "screenshots": ['
for f in "$SCREENSHOT_DIR"/*.png "$SCREENSHOT_DIR"/*.jpg "$SCREENSHOT_DIR"/*.jpeg; do
    if [ -f "$f" ]; then
        BASENAME=$(basename "$f")
        echo '            {"url": "'$REPO_URL/depictions/$PKG_ID/screenshots/$BASENAME'", "accessibilityText": "截图"},'
    fi
done
echo '          ]'
echo '        }'
echo '      ]'
echo '    }'
echo '  ]'
echo '}'
} > "$DEP_DIR/info.json"

echo ""
echo "信息已保存: $DEP_DIR/info.json"

echo ""
echo "==== 图标 ===="
if [ -f "$ICON_DIR/$PKG_ID.png" ]; then
    echo "已有图标"
    read -p "替换? (y/N): " REPLACE_ICON
    if [ "$REPLACE_ICON" = "y" ] || [ "$REPLACE_ICON" = "Y" ]; then
        read -p "图标路径: " ICON_PATH
        if [ -f "$ICON_PATH" ]; then
            cp "$ICON_PATH" "$ICON_DIR/$PKG_ID.png"
            echo "图标已更新"
        fi
    fi
else
    echo "还没有图标"
    read -p "图标路径 (回车跳过): " ICON_PATH
    if [ -n "$ICON_PATH" ] && [ -f "$ICON_PATH" ]; then
        cp "$ICON_PATH" "$ICON_DIR/$PKG_ID.png"
        echo "图标已添加"
    fi
fi

echo ""
echo "截图放: depictions/$PKG_ID/screenshots/"
echo "完事后运行: ./deploy.sh"
