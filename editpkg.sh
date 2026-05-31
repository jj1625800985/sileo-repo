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
    echo "可用插件:"
    echo ""
    i=1
    for f in "$ROOT_DIR/debs/"*.deb; do
        if [ -f "$f" ]; then
            name=$(basename "$f")
            echo "  [$i] $name"
            eval "FILE_$i=\$f"
            i=$((i+1))
        fi
    done
    echo ""
    printf "选择编号 (1-%d): " $((i-1))
    read sel
    if [ "$sel" -ge 1 ] 2>/dev/null && [ "$sel" -le $((i-1)) ] 2>/dev/null; then
        eval "INPUT=\"\$FILE_$sel\""
    else
        echo "无效选择"
        exit 1
    fi
else
    INPUT="$1"
fi

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

# 显示当前信息
echo ""
echo "==== 当前插件信息 ===="
if [ -f "$DEP_DIR/info.json" ]; then
    CURRENT_NAME=$(grep '"title"' "$DEP_DIR/info.json" | head -1 | sed 's/.*"title": "\(.*\)",/\1/')
    CURRENT_DESC=$(grep '"subheader"' "$DEP_DIR/info.json" | head -1 | sed 's/.*"title": "\(.*\)"/\1/')
    CURRENT_TEXT=$(grep -A5 '"DepictionTextView"' "$DEP_DIR/info.json" | grep '"text"' | head -1 | sed 's/.*"text": "\(.*\)"/\1/' | sed 's/\\n/\
/g')
    echo "  名称: $CURRENT_NAME"
    echo "  简介: $CURRENT_DESC"
    echo "  说明: $CURRENT_TEXT"
else
    CURRENT_NAME=""
    CURRENT_DESC=""
    CURRENT_TEXT=""
    echo "  (暂无信息，请填写)"
fi
echo "  图标: $(test -f "$ICON_DIR/$PKG_ID.png" && echo '有' || echo '无')"
echo "  截图: $(ls "$SCREENSHOT_DIR"/*.png "$SCREENSHOT_DIR"/*.jpg 2>/dev/null | wc -l) 张"
echo ""

echo "==== 填写插件信息 ===="

echo "▌ 第1步：插件名称（显示在 Sileo 列表里的名字）"
read -p "  名称 [$CURRENT_NAME]: " NAME
NAME="${NAME:-$CURRENT_NAME}"
[ -z "$NAME" ] && echo "插件名不能为空" && exit 1

echo "▌ 第2步：插件简介（一行概括，显示在名称下方）"
read -p "  简介 [$CURRENT_DESC]: " DESC
DESC="${DESC:-$CURRENT_DESC}"

echo "▌ 第3步：详细说明（点进去看到的描述，多行，输 . 结束）"
if [ -n "$CURRENT_TEXT" ]; then
    echo "  当前内容:"
    echo "  $CURRENT_TEXT" | sed 's/^/    /'
fi
echo "  (输入内容，回车换行，单独输 . 结束)"
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
    echo "已有图标，当前路径: icon/$PKG_ID.png"
    read -p "是否替换? (y/N): " REPLACE_ICON
    if [ "$REPLACE_ICON" = "y" ] || [ "$REPLACE_ICON" = "Y" ]; then
        read -p "新图标路径（拖拽图片到终端）: " ICON_PATH
        if [ -f "$ICON_PATH" ]; then
            cp "$ICON_PATH" "$ICON_DIR/$PKG_ID.png"
            echo "图标已更新"
        fi
    fi
else
    echo "还没有图标（在 Sileo 列表里显示的小图）"
    read -p "图标路径（拖拽图片到终端，回车跳过）: " ICON_PATH
    if [ -n "$ICON_PATH" ] && [ -f "$ICON_PATH" ]; then
        cp "$ICON_PATH" "$ICON_DIR/$PKG_ID.png"
        echo "图标已添加"
    fi
fi

echo ""
echo "==== 截图 ===="
echo "截图文件放到下面目录就行（支持 png/jpg）:"
echo "  depictions/$PKG_ID/screenshots/"
echo "放好后重新运行本脚本，自动识别截图"

echo ""
echo "==== 部署 ===="
echo "现在运行 ./deploy.sh 推送到 GitHub 就生效了"
