#!/bin/bash
#===============================================================
# 插件展示信息编辑工具
# 用法: ./editpkg.sh <包ID>
# 示例: ./editpkg.sh com.Axs.stheno
#===============================================================
set -e

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_URL="https://jj1625800985.github.io/sileo-repo"

if [ -z "$1" ]; then
    echo "❌ 用法: ./editpkg.sh <包ID>"
    echo "   示例: ./editpkg.sh com.Axs.stheno"
    echo ""
    echo "当前已有的包:"
    ls "$ROOT_DIR/depictions/" 2>/dev/null || echo "   (无)"
    exit 1
fi

PKG_ID="$1"
DEP_DIR="$ROOT_DIR/depictions/$PKG_ID"
SCREENSHOT_DIR="$DEP_DIR/screenshots"
ICON_DIR="$ROOT_DIR/icon"

# 如果包不存在，初始化
if [ ! -d "$DEP_DIR" ]; then
    echo "📦 新建插件: $PKG_ID"
    mkdir -p "$SCREENSHOT_DIR"
fi

# === 编辑展示信息 ===
echo ""
echo "========================================"
echo " 📝 填写插件信息"
echo "========================================"
echo "（直接回车保持不变）"
echo ""

# 读取现有值
if [ -f "$DEP_DIR/info.json" ]; then
    CURRENT_NAME=$(grep '"title"' "$DEP_DIR/info.json" | head -1 | sed 's/.*"title": "\(.*\)",/\1/')
    CURRENT_DESC=$(grep '"subheader"' "$DEP_DIR/info.json" | head -1 | sed 's/.*"title": "\(.*\)"/\1/')
    CURRENT_TEXT=$(grep -A5 '"DepictionTextView"' "$DEP_DIR/info.json" | grep '"text"' | head -1 | sed 's/.*"text": "\(.*\)"/\1/' | sed 's/\\n/\n/g')
else
    CURRENT_NAME=""
    CURRENT_DESC=""
    CURRENT_TEXT=""
fi

# 输入插件名
read -p "插件名称 [$CURRENT_NAME]: " NAME
NAME="${NAME:-$CURRENT_NAME}"
[ -z "$NAME" ] && echo "❌ 插件名不能为空" && exit 1

# 输入简介
read -p "插件简介 [$CURRENT_DESC]: " DESC
DESC="${DESC:-$CURRENT_DESC}"

# 输入详细说明（多行）
echo "详细说明（输入 . 结束）:"
echo "-------------------------"
if [ -n "$CURRENT_TEXT" ]; then
    echo "当前内容:"
    echo "$CURRENT_TEXT"
    echo "-------------------------"
fi
TEXT=""
while IFS= read -r line; do
    [ "$line" = "." ] && break
    [ -z "$TEXT" ] && TEXT="$line" || TEXT="$TEXT\n$line"
done
TEXT="${TEXT:-$CURRENT_TEXT}"

# === 生成 info.json ===
cat > "$DEP_DIR/info.json" <<EOF
{
  "minVersion": "16.0",
  "class": "DepictionTabView",
  "headerImage": "$REPO_URL/icon/$PKG_ID.png",
  "tintColor": "#4A90D9",
  "tabs": [
    {
      "tabname": "详情",
      "class": "DepictionStackView",
      "views": [
        {"class": "DepictionHeaderView", "title": "$NAME", "useBoldText": true},
        {"class": "DepictionSubheaderView", "title": "$DESC"},
        {"class": "DepictionSpacerView", "spacing": 8},
        {"class": "DepictionSeparatorView"},
        {"class": "DepictionHeaderView", "title": "说明"},
        {"class": "DepictionTextView", "text": "$TEXT"},
        {"class": "DepictionSpacerView", "spacing": 8},
        {"class": "DepictionSeparatorView"},
        {"class": "DepictionHeaderView", "title": "截图"},
        {
          "class": "DepictionScreenshotsView",
          "screenshots": [
$(for f in "$SCREENSHOT_DIR"/*.png "$SCREENSHOT_DIR"/*.jpg "$SCREENSHOT_DIR"/*.jpeg 2>/dev/null; do
  [ -f "$f" ] || continue
  BASENAME=$(basename "$f")
  echo "            {\"url\": \"$REPO_URL/depictions/$PKG_ID/screenshots/$BASENAME\", \"accessibilityText\": \"截图 ${BASENAME%.*}\"},"
done)
          ]
        }
      ]
    }
  ]
}
EOF

echo ""
echo "✅ 信息已保存到: $DEP_DIR/info.json"
echo ""

# === 图标 ===
echo "========================================"
echo " 🖼️  图标设置"
echo "========================================"
if [ -f "$ICON_DIR/$PKG_ID.png" ]; then
    echo "已有图标: icon/$PKG_ID.png"
    read -p "是否替换? (y/N): " REPLACE_ICON
    if [ "$REPLACE_ICON" = "y" ] || [ "$REPLACE_ICON" = "Y" ]; then
        read -p "图标文件路径: " ICON_PATH
        if [ -f "$ICON_PATH" ]; then
            cp "$ICON_PATH" "$ICON_DIR/$PKG_ID.png"
            echo "✅ 图标已更新"
        else
            echo "❌ 文件不存在"
        fi
    fi
else
    echo "⚠️  还没有图标"
    read -p "图标文件路径（直接回车跳过）: " ICON_PATH
    if [ -n "$ICON_PATH" ] && [ -f "$ICON_PATH" ]; then
        cp "$ICON_PATH" "$ICON_DIR/$PKG_ID.png"
        echo "✅ 图标已添加"
    fi
fi

# === 截图 ===
echo ""
echo "========================================"
echo " 📸 截图管理"
echo "========================================"
SCREENSHOT_COUNT=$(ls "$SCREENSHOT_DIR"/*.png "$SCREENSHOT_DIR"/*.jpg 2>/dev/null | wc -l)
echo "当前截图数: $SCREENSHOT_COUNT"
echo "存放位置: depictions/$PKG_ID/screenshots/"
echo ""
echo "操作:"
echo "  1. 复制截图文件到上面目录"
echo "  2. 命名随意，支持 png/jpg"
echo "  3. 重新运行本脚本自动识别"

echo ""
echo "========================================"
echo " 🚀 最后一步"
echo "========================================"
echo "运行 ./deploy.sh 推送到 GitHub 即可生效"
echo ""
