#!/bin/bash
#===============================================================
# Sileo Repo Auto-Update Script
# 扫描 debs/ 目录 → 生成 Packages / Release
# 支持 zstd 压缩的 .deb（如 Theos 构建的包）
#
# 用法:
#   ./scripts/update.sh              # 使用现有配置更新
#   ./scripts/update.sh -i           # 交互式配置 + 更新
#   ./scripts/update.sh --interactive
#   ./scripts/update.sh --config     # 仅交互式配置，不更新
#===============================================================

set -e

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEBS_DIR="$ROOT_DIR/debs"
REPO_CONFIG="$ROOT_DIR/repo.conf"

# 切换到仓库根目录，确保所有相对路径操作正确
cd "$ROOT_DIR"
INTERACTIVE_MODE=false
CONFIG_ONLY=false

# ---- 解析命令行参数 ----
for arg in "$@"; do
    case "$arg" in
        -i|--interactive) INTERACTIVE_MODE=true ;;
        --config)         INTERACTIVE_MODE=true; CONFIG_ONLY=true ;;
    esac
done

# ---- 默认配置 ----
DEFAULT_LABEL="jj1625800985 Repo"
DEFAULT_DESCRIPTION="jj1625800985's Sileo package repository"
DEFAULT_REPO_URL="https://jj1625800985.github.io/sileo-repo"

# 自动检测 git 远程名
detect_origin() {
    local remote
    remote="$(git remote 2>/dev/null | head -1)"
    echo "${remote:-origin}"
}

# ---- 加载配置文件 ----
load_config() {
    if [ -f "$REPO_CONFIG" ]; then
        source "$REPO_CONFIG"
        echo "[✓] 已加载配置: $REPO_CONFIG"
    else
        LABEL="$DEFAULT_LABEL"
        DESCRIPTION="$DEFAULT_DESCRIPTION"
        REPO_URL="$DEFAULT_REPO_URL"
        echo "[!] 未找到配置文件，使用默认值"
    fi
    ORIGIN="$(detect_origin)"
}

# ---- 保存配置文件 ----
save_config() {
    cat > "$REPO_CONFIG" <<EOF
# Sileo Repo 配置
# 可通过 ./scripts/update.sh --config 交互式修改
LABEL="$LABEL"
DESCRIPTION="$DESCRIPTION"
REPO_URL="$REPO_URL"
EOF
    echo "[✓] 配置已保存: $REPO_CONFIG"
}

# ---- 交互式配置 ----
interactive_config() {
    echo ""
    echo "========================================"
    echo "  仓库信息配置"
    echo "  留空则保持当前值不变"
    echo "========================================"
    echo ""

    read -r -p "Label   [$LABEL]: " input
    LABEL="${input:-$LABEL}"

    echo "Description (当前: $DESCRIPTION)"
    read -r -p "  新描述: " input
    DESCRIPTION="${input:-$DESCRIPTION}"

    read -r -p "Repo URL [$REPO_URL]: " input
    REPO_URL="${input:-$REPO_URL}"

    echo ""
    echo "========================================"
    echo "  配置预览"
    echo "========================================"
    echo "  Label:       $LABEL"
    echo "  Description: $DESCRIPTION"
    echo "  Repo URL:    $REPO_URL"
    echo "========================================"
    echo ""
    read -r -p "确认保存？(Y/n): " confirm
    case "$confirm" in
        n|N|no|NO) echo "已取消"; exit 0 ;;
        *) save_config ;;
    esac
}

# ---- 主流程开始 ----
echo "========================================"
echo " Sileo Repo Update"
echo "========================================"
echo "Root: $ROOT_DIR"
echo ""

# 加载现有配置
load_config

# 如果是 --config 模式，只配置不更新
if [ "$CONFIG_ONLY" = true ]; then
    interactive_config
    exit 0
fi

# 如果没有配置文件，或指定了 -i，进入交互模式
if [ ! -f "$REPO_CONFIG" ] || [ "$INTERACTIVE_MODE" = true ]; then
    interactive_config
fi

# 检查 debs 目录
DEB_COUNT=$(ls "$DEBS_DIR"/*.deb 2>/dev/null | wc -l)
if [ "$DEB_COUNT" -eq 0 ]; then
    echo "[!] debs/ 目录下没有 .deb 文件"
    echo "    请先将 .deb 放入 debs/ 目录"
    echo ""
    exit 1
fi
echo "[0/5] 检测到 $DEB_COUNT 个 .deb 包"
echo ""

# 清理可能存在的 root 权限旧文件
rm -f Packages Packages.bz2 Packages.gz Packages.xz Packages.lzma Packages.zst Release 2>/dev/null || true

# 1. 扫描 debs 生成 Packages
echo "[1/5] Generating Packages..."

# 检测是否有同名多版本包
MULTI_VERSION=false
PKG_NAMES=""
for deb in "$DEBS_DIR"/*.deb; do
    [ -f "$deb" ] || continue
    base=$(basename "$deb")
    # 提取包名：去掉 _版本号_架构.deb 后缀
    pkg_name="${base%_*}"
    pkg_name="${pkg_name%_*}"
    echo "$PKG_NAMES" | grep -q "$pkg_name" && MULTI_VERSION=true && break
    PKG_NAMES="$PKG_NAMES $pkg_name"
done

if [ "$MULTI_VERSION" = true ]; then
    echo "       (检测到多版本包，使用手动提取模式，确保所有版本保留)"
fi

GENERATED=false

# 先尝试 dpkg-scanpackages（标准 .deb，仅单版本时使用）
if [ "$MULTI_VERSION" = false ] && command -v dpkg-scanpackages &>/dev/null; then
    if dpkg-scanpackages debs/ > Packages 2>/dev/null; then
        GENERATED=true
    fi
fi

# 如果 dpkg-scanpackages 失败，手动提取（支持 zstd 格式的 .deb）
if [ "$GENERATED" = false ]; then
    CACHE_DIR="$ROOT_DIR/.cache"
    mkdir -p "$CACHE_DIR"
    EXTRACTED=0
    CACHED=0

    echo "       (提取 deb 控制信息...)"
    > Packages
    for deb in "$DEBS_DIR"/*.deb; do
        [ -f "$deb" ] || continue
        deb_name=$(basename "$deb")
        cache_file="$CACHE_DIR/${deb_name}.ctrl"

        # 判断是否需要重新提取
        NEED_EXTRACT=false
        if [ ! -f "$cache_file" ]; then
            NEED_EXTRACT=true
        else
            # deb 比缓存新 → 需要重提
            [ "$deb" -nt "$cache_file" ] && NEED_EXTRACT=true
        fi

        if [ "$NEED_EXTRACT" = true ]; then
            # 从 deb 中提取 control
            set +e
            CTRL_DATA=""
            for ctrl in control.tar.zst control.tar.gz control.tar.xz control.tar; do
                case "$ctrl" in
                    *.zst) CTRL_DATA=$(ar p "$deb" "$ctrl" 2>/dev/null | timeout 3 zstd -d 2>/dev/null | tar xO ./control 2>/dev/null) ;;
                    *.gz)  CTRL_DATA=$(ar p "$deb" "$ctrl" 2>/dev/null | tar xzO ./control 2>/dev/null) ;;
                    *.xz)  CTRL_DATA=$(ar p "$deb" "$ctrl" 2>/dev/null | tar xJO ./control 2>/dev/null) ;;
                    *)     CTRL_DATA=$(ar p "$deb" "$ctrl" 2>/dev/null | tar xO ./control 2>/dev/null) ;;
                esac
                if [ -n "$CTRL_DATA" ]; then
                    echo "$CTRL_DATA" > "$cache_file"
                    break
                fi
            done
            set -e
            EXTRACTED=$((EXTRACTED + 1))
        else
            CTRL_DATA=$(cat "$cache_file")
            CACHED=$((CACHED + 1))
        fi

        # 写入 Packages（无论从缓存还是新提取）
        if [ -n "$CTRL_DATA" ]; then
            SIZE=$(wc -c < "$deb")
            MD5=$(md5sum "$deb" | cut -d' ' -f1)
            SHA1=$(sha1sum "$deb" | cut -d' ' -f1)
            SHA256=$(sha256sum "$deb" | cut -d' ' -f1)
            PKG_ID=$(echo "$CTRL_DATA" | grep -i "^Package:" | head -1 | cut -d' ' -f2)
            echo "$CTRL_DATA"
            echo "Filename: ./debs/$deb_name"
            echo "Size: $SIZE"
            echo "MD5sum: $MD5"
            echo "SHA1: $SHA1"
            echo "SHA256: $SHA256"
            echo ""
        fi
    done >> Packages
    echo "       提取 $EXTRACTED 个，缓存命中 $CACHED 个"
fi

# 后处理：只对缺失的包补充 SileoDepiction 和 Icon 字段
# 已有的保留不动（如外部 depiction 链接），避免破坏原本正常的显示
awk -v url="$REPO_URL" '
/^Package: / {
    if (pkg != "") {
        if (needs_dep) print "Sileodepiction: " url "/depictions/" pkg "/info.json"
        if (needs_icon) print "Icon: " url "/icon/" pkg ".png"
    }
    pkg = substr($0, index($0, ": ") + 2)
    needs_dep = 1; needs_icon = 1
    print
    next
}
/[Ss]ileo[dD]epiction: / { needs_dep = 0; print; next }
/^Icon: / { needs_icon = 0; print; next }
/^Depiction: / { print; next }  # 保留 Depiction 字段
/^$/ {
    if (pkg != "") {
        if (needs_dep) print "Sileodepiction: " url "/depictions/" pkg "/info.json"
        if (needs_icon) print "Icon: " url "/icon/" pkg ".png"
        pkg = ""; needs_dep = 0; needs_icon = 0
    }
    print; next
}
{ print }
END {
    if (pkg != "") {
        if (needs_dep) print "Sileodepiction: " url "/depictions/" pkg "/info.json"
        if (needs_icon) print "Icon: " url "/icon/" pkg ".png"
    }
}
' Packages > Packages.tmp && mv Packages.tmp Packages

echo "       Packages generated."

# 2. 生成 depictions 详情页 + 复制图标
echo "[2/5] Generating depictions & icons..."

mkdir -p icon depictions
DEFAULT_ICON="icon/myicon.png"

# 清除过期的 depiction（deb 或 screenshots 比 info.json 新 → 删除）
STALE_COUNT=0
for deb in "$DEBS_DIR"/*.deb; do
    [ -f "$deb" ] || continue
    deb_name=$(basename "$deb")
    pkg_id="${deb_name%_*}"
    pkg_id="${pkg_id%_*}"
    dep_file="depictions/$pkg_id/info.json"
    if [ -f "$dep_file" ]; then
        NEED_REGEN=false
        [ "$deb" -nt "$dep_file" ] && NEED_REGEN=true
        # 截图目录变更也要重新生成
        ss_dir="depictions/$pkg_id/screenshots"
        [ -d "$ss_dir" ] && [ "$(find "$ss_dir" -type f -newer "$dep_file" 2>/dev/null | head -1)" != "" ] && NEED_REGEN=true
        # 更新日志变更也要重新生成
        cl_file="depictions/$pkg_id/changelog.md"
        [ -f "$cl_file" ] && [ "$cl_file" -nt "$dep_file" ] && NEED_REGEN=true
        if [ "$NEED_REGEN" = true ]; then
            rm -f "$dep_file"
            STALE_COUNT=$((STALE_COUNT + 1))
        fi
    fi
done
if [ "$STALE_COUNT" -gt 0 ]; then
    echo "       过期 $STALE_COUNT 个"
fi

# 解析 Packages，为每个包生成 depiction JSON + 处理图标
awk -v url="$REPO_URL" -v defaultIcon="$DEFAULT_ICON" '
function val(line) {
    idx = index(line, ": ")
    if (idx > 0) return substr(line, idx + 2)
    return ""
}
function jsonEscape(s) {
    gsub(/\\/, "\\\\", s)
    gsub(/"/, "\\\"", s)
    gsub(/\t/, " ", s)
    gsub(/\r/, "", s)
    gsub(/\n/, "\\n", s)
    return s
}
function trim(s) {
    gsub(/^[ \t]+|[ \t]+$/, "", s)
    return s
}
function readFile(path) {
    result = ""
    while ((getline line < path) > 0) {
        if (result != "") result = result "\\n"
        result = result jsonEscape(line)
    }
    close(path)
    return result
}
function hashColor(str) {
    if (str == "") return "#4A90D9"
    h = 0
    for (c = 1; c <= length(str); c++) {
        ch = substr(str, c, 1)
        h = (h * 31 + index("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789", ch)) % 6
    }
    if (h < 1) h = 1
    split("#4A90D9 #7ED321 #F5A623 #D0021B #9013FE #50E3C2", tc)
    return tc[h]
}
{
    # Packages 格式：每行 "Key: Value"，空行分割包记录
    if ($0 ~ /^Package: /) {
        if (pkg != "") generate()
        pkg = val($0)
        name = ""; desc = ""; section = ""; version = ""; author = ""
    } else if ($0 ~ /^Name: /) {
        name = val($0)
    } else if ($0 ~ /^Version: /) {
        version = val($0)
    } else if ($0 ~ /^Section: /) {
        section = val($0)
    } else if ($0 ~ /^Author: /) {
        author = val($0)
    } else if ($0 ~ /^Description: /) {
        desc = val($0)
    } else if ($0 ~ /^[^ ]/ && $0 !~ /^$/) {
        # 遇到新的顶层键值不匹配（如 MD5sum：），但 Package 已经收集了，可能是空行分隔未正确处理
        if (pkg != "" && $0 ~ /^[A-Za-z]+: / && $0 !~ /^ *(Package|Name|Version|Section|Author|Description|Filename|Size|MD5|SHA|Installed)/) {
            # 非标准字段，跳过
        }
    }
}
END {
    if (pkg != "") generate()
}
function generate() {
    if (pkg == "") return
    if (name == "") name = pkg

    pDir = "depictions/" pkg
    system("mkdir -p " pDir)
    jFile = pDir "/info.json"

    # 缓存命中：info.json 已存在且未过期
    if (system("test -f \"" jFile "\"") == 0) {
        # 仍需要处理图标
        iFile = "icon/" pkg ".png"
        if (system("test -f \"" iFile "\"") != 0 && system("test -f \"" defaultIcon "\"") == 0) {
            system("cp \"" defaultIcon "\" \"" iFile "\"")
        }
        pkg = ""
        return
    }

    # 检测截图：depictions/<pkg>/screenshots/ 目录下的 png
    ss_dir = pDir "/screenshots"
    system("mkdir -p " ss_dir)
    ss_count = 0
    for (i = 1; i <= 10; i++) {
        if (system("test -f \"" ss_dir "/" i ".png\"") == 0) ss_count++
    }

    printf "       [生成] depictions/%s/info.json", pkg
    if (ss_count > 0) printf " (%d 张截图)", ss_count
    printf "\n"

    iconUrl = url "/icon/" pkg ".png"
    tColor = hashColor(section)
    eName = jsonEscape(name)
    eDesc = jsonEscape(desc)
    eSection = jsonEscape(section)
    eAuthor = jsonEscape(author)
    eVers = jsonEscape(version)

    print "{" > jFile
    print "  \"class\": \"DepictionTabView\"," > jFile
    print "  \"minVersion\": \"0.1\"," > jFile
    printf "  \"headerImage\": \"%s\",\n", iconUrl > jFile
    printf "  \"tintColor\": \"%s\",\n", tColor > jFile
    print "  \"tabs\": [" > jFile
    print "    {" > jFile
    print "      \"tabname\": \"插件信息\"," > jFile
    print "      \"class\": \"DepictionStackView\"," > jFile
    print "      \"views\": [" > jFile
    # 截图区域（有截图时才显示）
    if (ss_count > 0) {
        print "        {" > jFile
        print "          \"itemCornerRadius\": 6," > jFile
        print "          \"itemSize\": \"{320, 275.41333333333336}\"," > jFile
        print "          \"screenshots\": [" > jFile
        for (i = 1; i <= ss_count; i++) {
            comma = (i < ss_count ? "," : "")
            printf "            {\"url\": \"%s/depictions/%s/screenshots/%d.png\", \"accessibilityText\": \"截图 %d\", \"fullSizeURL\": \"%s/depictions/%s/screenshots/%d.png\"}%s\n", url, pkg, i, i, url, pkg, i, comma > jFile
        }
        print "          ]," > jFile
        print "          \"class\": \"DepictionScreenshotsView\"" > jFile
        print "        }," > jFile
        print "        {\"class\": \"DepictionSeparatorView\"}," > jFile
    }
    # 说明
    if (eDesc != "") {
        print "        {\"title\": \"说明\", \"class\": \"DepictionHeaderView\"}," > jFile
        printf "        {\"class\": \"DepictionMarkdownView\", \"markdown\": \"%s\"},\n", eDesc > jFile
        print "        {\"class\": \"DepictionSeparatorView\"}," > jFile
    }
    # 信息
    print "        {\"title\": \"信息\", \"class\": \"DepictionHeaderView\"}," > jFile
    if (eName != "") {
        printf "        {\"title\": \"名称\", \"text\": \"%s\", \"class\": \"DepictionTableTextView\"},\n", eName > jFile
    }
    printf "        {\"title\": \"版本\", \"text\": \"%s\", \"class\": \"DepictionTableTextView\"},\n", eVers > jFile
    printf "        {\"title\": \"包名\", \"text\": \"%s\", \"class\": \"DepictionTableTextView\"},\n", pkg > jFile
    if (eAuthor != "") {
        printf "        {\"title\": \"作者\", \"text\": \"%s\", \"class\": \"DepictionTableTextView\"},\n", eAuthor > jFile
    }
    print "        {\"spacing\": 20, \"class\": \"DepictionSpacerView\"}" > jFile
    print "      ]" > jFile
    print "    }," > jFile

    # 更新日志 tab
    changelog_file = pDir "/changelog.md"
    changelog = ""
    if (system("test -f \"" changelog_file "\"") == 0) {
        changelog = readFile(changelog_file)
    }
    if (changelog == "") changelog = "暂无更新日志"

    print "    {" > jFile
    print "      \"tabname\": \"更新日志\"," > jFile
    print "      \"class\": \"DepictionStackView\"," > jFile
    print "      \"views\": [" > jFile
    print "        {\"title\": \"更新日志\", \"class\": \"DepictionHeaderView\"}," > jFile
    printf "        {\"class\": \"DepictionMarkdownView\", \"markdown\": \"%s\"},\n", changelog > jFile
    print "        {\"class\": \"DepictionSeparatorView\"}," > jFile
    print "        {\"spacing\": 20, \"class\": \"DepictionSpacerView\"}" > jFile
    print "      ]" > jFile
    print "    }" > jFile
    print "  ]" > jFile
    print "}" > jFile
    close(jFile)

    # 图标：没有专属图标就用默认
    iFile = "icon/" pkg ".png"
    if (system("test -f \"" iFile "\"") != 0 && system("test -f \"" defaultIcon "\"") == 0) {
        system("cp \"" defaultIcon "\" \"" iFile "\"")
        printf "       [图标] icon/%s.png (使用默认图标)\n", pkg
    }
    pkg = ""
}
' Packages

echo "       depictions & icons done."

# 3. 压缩 Packages
echo "[3/5] Compressing Packages..."
bzip2 -fzk Packages
gzip  -fk Packages    # Packages.gz
xz    -fzk Packages   # Packages.xz  (Sileo 推荐)
command -v lzma &>/dev/null && lzma -fzk Packages || echo "       (lzma not installed, skipped)"
command -v zstd &>/dev/null && zstd -fk Packages || echo "       (zstd not installed, skipped)"
echo "       bz2 gz xz lzma zst done."

# 4. 计算校验和
echo "[4/5] Calculating checksums..."
PACKAGES_SIZE=$(wc -c < Packages 2>/dev/null || echo 0)

MD5SUM=$(md5sum Packages 2>/dev/null | cut -d' ' -f1 || md5 Packages 2>/dev/null | cut -d'=' -f2 | tr -d ' ')
SHA1SUM=$(sha1sum Packages 2>/dev/null | cut -d' ' -f1)
SHA256SUM=$(sha256sum Packages 2>/dev/null | cut -d' ' -f1)

# 5. 生成 Release 文件（使用配置中的值）
echo "[5/5] Writing Release file..."
cat > Release <<EOF
Origin: $ORIGIN
Label: $LABEL
Suite: stable
Version: 1.0
Codename: ios
Architectures: iphoneos-arm iphoneos-arm64 iphoneos-arm64e
Components: main
Description: $DESCRIPTION
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
echo "Current Sileo display:"
echo "  源名称:  $LABEL"
echo "  描述:    $DESCRIPTION"
echo "  地址:    $REPO_URL"
echo ""
echo "Next steps:"
echo "   1. Add .deb files to debs/"
echo "   2. Run ./scripts/update.sh"
echo "   3. Commit & push to GitHub"
echo "   4. Enable GitHub Pages (main branch, /root)"
echo "   5. Add source in Sileo:"
echo "      $REPO_URL"
echo ""
