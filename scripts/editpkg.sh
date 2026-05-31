#!/bin/bash
#===============================================================
# 插件展示信息编辑工具
# 用法: ./editpkg.sh <包ID 或 .deb文件>
# 示例: ./editpkg.sh com.Axs.stheno
#       ./editpkg.sh debs/xxx.deb
#===============================================================
set -e

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

# 从 repo.conf 加载 REPO_URL
REPO_CONFIG="$ROOT_DIR/repo.conf"
REPO_URL="https://jj1625800985.github.io/sileo-repo"
if [ -f "$REPO_CONFIG" ]; then
    source "$REPO_CONFIG"
fi

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
        ar p "$INPUT" "$ctrl" >/tmp/pkgctl 2>/dev/null || continue
        EXTRACTED=""
        case "$ctrl" in
            *.zst) EXTRACTED=$(zstd -d < /tmp/pkgctl 2>/dev/null | tar xO ./control 2>/dev/null) ;;
            *.gz)  EXTRACTED=$(tar xzO ./control </tmp/pkgctl 2>/dev/null) ;;
            *.xz)  EXTRACTED=$(tar xJO ./control </tmp/pkgctl 2>/dev/null) ;;
            *)     EXTRACTED=$(tar xO ./control </tmp/pkgctl 2>/dev/null) ;;
        esac
        if [ -n "$EXTRACTED" ]; then
            VERSION=$(echo "$EXTRACTED" | grep "^Version:" | sed 's/Version: *//')
            AUTHOR=$(echo "$EXTRACTED" | grep "^Author:" | sed 's/Author: *//')
            PKG_ID=$(echo "$EXTRACTED" | grep "^Package:" | sed 's/Package: *//')
            break
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
    # 尝试从 Packages 读取版本
    VERSION=$(grep -A5 "^Package: $PKG_ID$" "$ROOT_DIR/Packages" 2>/dev/null | grep "^Version:" | head -1 | sed 's/Version: *//' || echo "")
    AUTHOR=$(grep -A5 "^Package: $PKG_ID$" "$ROOT_DIR/Packages" 2>/dev/null | grep "^Author:" | head -1 | sed 's/Author: *//' || echo "")
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
    CURRENT_NAME=$(grep '"title"' "$DEP_DIR/info.json" | head -1 | sed 's/.*"title": "\([^"]*\)".*/\1/')
    CURRENT_DESC=$(grep 'DepictionSubheaderView' "$DEP_DIR/info.json" | head -1 | sed 's/.*"title": "\([^"]*\)".*/\1/')
    CURRENT_TEXT=$(grep '"markdown":' "$DEP_DIR/info.json" | head -1 | sed 's/.*"markdown": "\([^"]*\)".*/\1/' | sed 's/\\n/\
/g')
    # 读取更新日志
    if [ -f "$DEP_DIR/changelog.md" ]; then
        CURRENT_CHANGELOG=$(cat "$DEP_DIR/changelog.md")
    else
        CURRENT_CHANGELOG=""
    fi
    echo "  名称: $CURRENT_NAME"
    echo "  简介: $CURRENT_DESC"
    echo "  说明: $CURRENT_TEXT"
    echo "  更新日志: $(test -f "$DEP_DIR/changelog.md" && echo '有' || echo '无')"
else
    CURRENT_NAME=""
    CURRENT_DESC=""
    CURRENT_TEXT=""
    CURRENT_CHANGELOG=""
    echo "  (暂无信息，请填写)"
fi
echo "  图标: $(test -f "$ICON_DIR/$PKG_ID.png" && echo '有' || echo '无')"
echo "  截图: $(ls "$SCREENSHOT_DIR"/*.png "$SCREENSHOT_DIR"/*.jpg 2>/dev/null | wc -l) 张"
echo ""

# 初始化变量
NAME="${CURRENT_NAME:-}"
DESC="${CURRENT_DESC:-}"
TEXT="${CURRENT_TEXT:-}"
CHANGELOG="${CURRENT_CHANGELOG:-}"

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
    echo "  [6] 更新日志"
    echo "  [7] 全部重新填"
    echo "  [0] ✓ 完成保存"
    echo ""
    read -p "选择 (0-7): " choice

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
            echo "更新日志（多行 markdown，输 . 结束）:"
            if [ -n "$CHANGELOG" ]; then
                echo "当前:"
                echo "$CHANGELOG" | sed 's/^/  /'
            fi
            CHANGELOG=""
            while IFS= read -r line; do
                [ "$line" = "." ] && break
                [ -z "$CHANGELOG" ] && CHANGELOG="$line" || CHANGELOG="$CHANGELOG
$line"
            done
            [ -z "$CHANGELOG" ] && CHANGELOG="${CURRENT_CHANGELOG:-}"
            ;;
        7)
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
            echo "更新日志（多行 markdown，输 . 结束）:"
            CHANGELOG=""
            while IFS= read -r line; do
                [ "$line" = "." ] && break
                [ -z "$CHANGELOG" ] && CHANGELOG="$line" || CHANGELOG="$CHANGELOG
$line"
            done
            [ -z "$CHANGELOG" ] && CHANGELOG="${CURRENT_CHANGELOG:-}"
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

# 转义更新日志
CHANGELOG_JSON="暂无更新日志"
if [ -n "$CHANGELOG" ]; then
    # 保存 changelog.md
    echo "$CHANGELOG" > "$DEP_DIR/changelog.md"
    CHANGELOG_JSON=$(echo "$CHANGELOG" | sed 's/\\/\\\\/g; s/"/\\"/g; s/$/\\n/' | tr -d '\n')
    CHANGELOG_JSON="${CHANGELOG_JSON%\\n}"
fi

# 生成 info.json（参照 rootless.002599.xyz 源格式）
{
echo "{"
echo '  "minVersion": "0.1",'
echo '  "tabs": ['
echo '    {'
echo '      "tabname": "插件信息",'
echo '      "class": "DepictionStackView",'
echo '      "views": ['
if ls "$SCREENSHOT_DIR"/*.png "$SCREENSHOT_DIR"/*.jpg "$SCREENSHOT_DIR"/*.jpeg 2>/dev/null | head -1 >/dev/null; then
echo '        {'
echo '          "itemCornerRadius": 6,'
echo '          "itemSize": "{320, 275.41333333333336}",'
echo '          "screenshots": ['
FIRST=true
for f in "$SCREENSHOT_DIR"/*.png "$SCREENSHOT_DIR"/*.jpg "$SCREENSHOT_DIR"/*.jpeg; do
    if [ -f "$f" ]; then
        BASENAME=$(basename "$f")
        COM=","
        $FIRST && COM="" && FIRST=false
        echo '            {"url": "'$REPO_URL/depictions/$PKG_ID/screenshots/$BASENAME'", "accessibilityText": "截图", "fullSizeURL": "'$REPO_URL/depictions/$PKG_ID/screenshots/$BASENAME'"}'
    fi
done
echo '          ],'
echo '          "class": "DepictionScreenshotsView"'
echo '        },'
echo '        {"class": "DepictionSeparatorView"},'
fi
echo '        {"title": "说明", "class": "DepictionHeaderView"},'
echo '        {"class": "DepictionMarkdownView", "markdown": "'$TEXT_JSON'"},'
echo '        {"class": "DepictionSeparatorView"},'
echo '        {"title": "信息", "class": "DepictionHeaderView"},'
echo '        {"title": "名称", "text": "'$NAME'", "class": "DepictionTableTextView"},'
echo '        {"title": "版本", "text": "'$VERSION'", "class": "DepictionTableTextView"},'
echo '        {"title": "包名", "text": "'$PKG_ID'", "class": "DepictionTableTextView"},'
if [ -n "$AUTHOR" ]; then echo '        {"title": "作者", "text": "'$AUTHOR'", "class": "DepictionTableTextView"},'; fi
echo '        {"spacing": 20, "class": "DepictionSpacerView"}'
echo '      ]'
echo '    },'
echo '    {'
echo '      "tabname": "更新日志",'
echo '      "class": "DepictionStackView",'
echo '      "views": ['
echo '        {'
echo '          "class": "DepictionLayerView",'
echo '          "views": ['
echo '            {"text": "更新日志", "class": "DepictionLabelView", "fontWeight": "bold", "fontSize": 16}'
echo '          ]'
echo '        },'
echo '        {"class": "DepictionMarkdownView", "markdown": "'$CHANGELOG_JSON'"},'
echo '        {"class": "DepictionSeparatorView"}'
echo '      ]'
echo '    }'
echo '  ],'
echo '  "class": "DepictionTabView"'
echo '}'
} > "$DEP_DIR/info.json"

echo ""
echo "✅ 信息已保存: $DEP_DIR/info.json"
echo ""
echo "运行 ./deploy.sh 推送到 GitHub 即生效"
echo "   (或: cd .. && bash deploy.sh)"
