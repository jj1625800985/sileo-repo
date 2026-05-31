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
            EXTRACTED=""
            if tar --zstd -xO ./control </tmp/pkgctl >/dev/null 2>&1; then
                EXTRACTED=$(tar --zstd -xO ./control </tmp/pkgctl 2>/dev/null)
            elif tar xzO ./control </tmp/pkgctl >/dev/null 2>&1; then
                EXTRACTED=$(tar xzO ./control </tmp/pkgctl 2>/dev/null)
            elif tar xJO ./control </tmp/pkgctl >/dev/null 2>&1; then
                EXTRACTED=$(tar xJO ./control </tmp/pkgctl 2>/dev/null)
            elif tar xO ./control </tmp/pkgctl >/dev/null 2>&1; then
                EXTRACTED=$(tar xO ./control </tmp/pkgctl 2>/dev/null)
            fi
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

# 初始化变量
NAME="${CURRENT_NAME:-}"
DESC="${CURRENT_DESC:-}"
TEXT="${CURRENT_TEXT:-}"

# 如果是新插件，先填基础信息
if [ -z "$NAME" ]; then
    echo "==== 新建插件 ===="
    read -p "插件名称: " NAME
    [ -z "$NAME" ] && echo "插件名不能为空" && exit 1
    read -p "插件简介: " DESC
    echo "详细说明（多行，输 . 结束）:"
    TEXT=""
    while IFS= read -r line; do
        [ "$line" = "." ] && break
        [ -z "$TEXT" ] && TEXT="$line" || TEXT="$TEXT
$line"
    done
fi

# 菜单循环
while true; do
    echo ""
    echo "==== 编辑菜单 ===="
    echo "  [1] 插件名称  → $NAME"
    echo "  [2] 插件简介  → ${DESC:-无}"
    echo "  [3] 详细说明"
    echo "  [4] 图标      → $(test -f "$ICON_DIR/$PKG_ID.png" && echo '已有' || echo '无')"
    echo "  [5] 添加截图  → $(ls "$SCREENSHOT_DIR"/*.png "$SCREENSHOT_DIR"/*.jpg 2>/dev/null | wc -l | tr -d ' ') 张"
    echo "  [6] 全部重新填"
    echo "  [0] ✓ 完成保存"
    echo ""
    read -p "选择 (0-6): " choice

    case "$choice" in
        1)
            read -p "新名称 [$NAME]: " newval
            NAME="${newval:-$NAME}"
            [ -z "$NAME" ] && echo "名称不能为空"
            ;;
        2)
            read -p "新简介 [$DESC]: " newval
            DESC="${newval:-$DESC}"
            ;;
        3)
            echo "详细说明（多行，输 . 结束）:"
            if [ -n "$TEXT" ]; then
                echo "当前:"
                echo "  $TEXT" | sed 's/^/  /'
            fi
            TEXT=""
            while IFS= read -r line; do
                [ "$line" = "." ] && break
                [ -z "$TEXT" ] && TEXT="$line" || TEXT="$TEXT
$line"
            done
            [ -z "$TEXT" ] && TEXT="${CURRENT_TEXT:-}"
            ;;
        4)
            if [ -f "$ICON_DIR/$PKG_ID.png" ]; then
                read -p "替换图标? (y/N): " yn
                if [ "$yn" = "y" ] || [ "$yn" = "Y" ]; then
                    read -p "图片路径: " ICON_PATH
                    [ -f "$ICON_PATH" ] && cp "$ICON_PATH" "$ICON_DIR/$PKG_ID.png" && echo "图标已替换"
                fi
            else
                read -p "图标路径: " ICON_PATH
                [ -f "$ICON_PATH" ] && cp "$ICON_PATH" "$ICON_DIR/$PKG_ID.png" && echo "图标已添加"
            fi
            ;;
        5)
            echo "截图放到: depictions/$PKG_ID/screenshots/"
            echo "放好后重新选本选项，自动识别"
            ;;
        6)
            read -p "插件名称: " NAME
            [ -z "$NAME" ] && NAME="${CURRENT_NAME:-}" && echo "保留原名"
            read -p "插件简介: " DESC
            [ -z "$DESC" ] && DESC="${CURRENT_DESC:-}"
            echo "详细说明（多行，输 . 结束）:"
            TEXT=""
            while IFS= read -r line; do
                [ "$line" = "." ] && break
                [ -z "$TEXT" ] && TEXT="$line" || TEXT="$TEXT
$line"
            done
            [ -z "$TEXT" ] && TEXT="${CURRENT_TEXT:-}"
            ;;
        0)
            break
            ;;
        *)
            echo "无效选择"
            ;;
    esac
done

# 转义换行和引号，保证 JSON 格式正确
[ -z "$TEXT" ] && TEXT=""
TEXT_JSON=$(echo "$TEXT" | sed 's/\\/\\\\/g; s/"/\\"/g; s/$/\\n/' | tr -d '\n')
TEXT_JSON="${TEXT_JSON%\\n}"

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
echo '        {"class": "DepictionTextView", "text": "'$TEXT_JSON'"},'
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
echo "✅ 信息已保存: $DEP_DIR/info.json"
echo ""
echo "运行 ./deploy.sh 推送到 GitHub 即生效"
