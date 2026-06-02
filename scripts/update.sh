#!/bin/bash
#===============================================================
# Sileo Repo Auto-Update Script (优化版)
# 扫描 debs/ 目录 → 生成 Packages / Release
# 支持 zstd 压缩的 .deb（如 Theos 构建的包）
#
# 优化特性:
#   - 并行压缩（bzip2/gzip/xz/lzma/zstd 同时运行）
#   - 校验和 + Release 生成使用数组循环，减少 200+ 行重复
#   - awk 中预检测文件状态，减少 system() 调用
#   - DESCRIPTION 自动从包描述补全
#   - 动态步骤计数
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
DEFAULT_SUITE="sxllm"

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
        SUITE="$DEFAULT_SUITE"
        echo "[!] 未找到配置文件，使用默认值"
    fi
    ORIGIN="${ORIGIN:-$(detect_origin)}"
}

# ---- 保存配置文件 ----
save_config() {
    cat > "$REPO_CONFIG" <<EOF
# Sileo Repo 配置
# 可通过 ./scripts/update.sh --config 交互式修改
ORIGIN="$ORIGIN"
LABEL="$LABEL"
SUITE="$SUITE"
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

    read -r -p "Origin  [$ORIGIN]: " input
    ORIGIN="${input:-$ORIGIN}"

    read -r -p "Label   [$LABEL]: " input
    LABEL="${input:-$LABEL}"

    read -r -p "Suite   [$SUITE]: " input
    SUITE="${input:-$SUITE}"

    echo "Description (当前: $DESCRIPTION)"
    read -r -p "  新描述: " input
    DESCRIPTION="${input:-$DESCRIPTION}"

    read -r -p "Repo URL [$REPO_URL]: " input
    REPO_URL="${input:-$REPO_URL}"

    echo ""
    echo "========================================"
    echo "  配置预览"
    echo "========================================"
    echo "  Origin:      $ORIGIN"
    echo "  Label:       $LABEL"
    echo "  Suite:       $SUITE"
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

# ---- 辅助：DESCRIPTION 自动补全 ----
# 如果 DESCRIPTION 是占位值，尝试从最新包提取描述
auto_fill_description() {
    if [ "$DESCRIPTION" = "无" ] || [ "$DESCRIPTION" = "" ]; then
        local latest_pkg
        latest_pkg=$(ls -t "$DEBS_DIR"/*.deb 2>/dev/null | head -1)
        if [ -n "$latest_pkg" ]; then
            local pkg_desc
            pkg_desc=$(ar p "$latest_pkg" control.tar.zst 2>/dev/null | timeout 3 zstd -d 2>/dev/null | tar xO ./control 2>/dev/null | grep -i "^Description:" | head -1 | cut -d' ' -f2-)
            if [ -z "$pkg_desc" ]; then
                pkg_desc=$(ar p "$latest_pkg" control.tar.gz 2>/dev/null | tar xzO ./control 2>/dev/null | grep -i "^Description:" | head -1 | cut -d' ' -f2-)
            fi
            if [ -n "$pkg_desc" ]; then
                DESCRIPTION="$pkg_desc"
                echo "[i] DESCRIPTION 已自动更新为: $DESCRIPTION"
            fi
        fi
    fi
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

# DESCRIPTION 自动补全
auto_fill_description

# 动态步骤计数
TOTAL_STEPS=6
CURRENT_STEP=0

# 检查 debs 目录
DEB_COUNT=$(ls "$DEBS_DIR"/*.deb 2>/dev/null | wc -l)
if [ "$DEB_COUNT" -eq 0 ]; then
    echo "[!] debs/ 目录下没有 .deb 文件"
    echo "    请先将 .deb 放入 debs/ 目录"
    echo ""
    exit 1
fi
echo "[$CURRENT_STEP/$TOTAL_STEPS] 检测到 $DEB_COUNT 个 .deb 包"
echo ""

# 修复之前可能由 sudo 留下的 root 权限文件（否则 awk 写入会失败）
for dir in depictions icon .cache; do
    if [ -d "$dir" ] && [ -n "$(find "$dir" -user root 2>/dev/null | head -1)" ]; then
        echo "       (修复 $dir 下 root 权限文件...)"
        echo "q" | sudo -S chown -R mobile:mobile "$dir" 2>/dev/null || true
    fi
done

# 清理旧文件
rm -f Packages Packages.bz2 Packages.gz Packages.xz Packages.lzma Packages.zst Release 2>/dev/null || true

# 清理 stale .cache（对应 .deb 已删除的缓存项）
CACHE_DIR="$ROOT_DIR/.cache"
if [ -d "$CACHE_DIR" ]; then
    for cf in "$CACHE_DIR"/*.ctrl; do
        [ -f "$cf" ] || continue
        deb_name=$(basename "$cf" .ctrl)
        if [ ! -f "$DEBS_DIR/$deb_name" ]; then
            rm -f "$cf"
            echo "       (清除过期缓存: $deb_name)"
        fi
    done
fi

# ---- Step 1: 生成 Packages（手动提取，支持所有压缩格式 + SHA512） ----
CURRENT_STEP=$((CURRENT_STEP + 1))
echo "[$CURRENT_STEP/$TOTAL_STEPS] Generating Packages..."

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
            SHA512=$(sha512sum "$deb" | cut -d' ' -f1)
            PKG_ID=$(echo "$CTRL_DATA" | grep -i "^Package:" | head -1 | cut -d' ' -f2)
            echo "$CTRL_DATA"
            echo "Filename: debs/$deb_name"
            echo "Size: $SIZE"
            echo "MD5sum: $MD5"
            echo "SHA1: $SHA1"
            echo "SHA256: $SHA256"
            echo "SHA512: $SHA512"
            echo ""
        fi
    done >> Packages
    echo "       提取 $EXTRACTED 个，缓存命中 $CACHED 个"

# 后处理：只对缺失的包补充 SileoDepiction 和 Icon 字段
# 已有的保留不动（如外部 depiction 链接），避免破坏原本正常的显示
awk -v url="$REPO_URL" '
/^Package: / {
    if (pkg != "") {
        if (needs_dep) print "SileoDepiction: " url "/depictions/" pkg "/info.json"
        if (needs_icon) print "Icon: " url "/icon/" pkg ".png"
    }
    pkg = substr($0, index($0, ": ") + 2)
    needs_dep = 1; needs_icon = 1
    print
    next
}
/^[Ss]ileo[dD]epiction: / { needs_dep = 0; print; next }
/^Icon: / { needs_icon = 0; print; next }
/^Depiction: / { print; next }  # 保留 Depiction 字段
/^$/ {
    if (pkg != "") {
        if (needs_dep) print "SileoDepiction: " url "/depictions/" pkg "/info.json"
        if (needs_icon) print "Icon: " url "/icon/" pkg ".png"
        pkg = ""; needs_dep = 0; needs_icon = 0
    }
    print; next
}
{ print }
END {
    if (pkg != "") {
        if (needs_dep) print "SileoDepiction: " url "/depictions/" pkg "/info.json"
        if (needs_icon) print "Icon: " url "/icon/" pkg ".png"
    }
}
' Packages > Packages.tmp && mv Packages.tmp Packages

# 去重：每个包只保留最新版本
echo "       (Deduplicating: keeping only latest version per package...)"
awk '
BEGIN {
    pkg_count = 0
    sep = ""
}
/^Package: / {
    if (rec != "") save_rec()
    pkg = substr($0, index($0, ": ") + 2)
    rec = $0 "\n"
    next
}
/^$/ {
    next
}
{
    if (rec != "") rec = rec $0 "\n"
}
END {
    if (rec != "") save_rec()
    for (i = 0; i < pkg_count; i++) {
        printf "%s", records[i]
        if (i < pkg_count - 1) printf "\n"
    }
}
function save_rec() {
    ver = ""
    n = split(rec, lines, "\n")
    for (i = 1; i <= n; i++) {
        if (lines[i] ~ /^Version: /) {
            ver = substr(lines[i], index(lines[i], ": ") + 2)
            break
        }
    }
    for (i = 0; i < pkg_count; i++) {
        if (pkg_names[i] == pkg) {
            cmd = "dpkg --compare-versions \"" ver "\" gt \"" pkg_vers[i] "\" 2>/dev/null"
            if (system(cmd) == 0) {
                pkg_vers[i] = ver
                records[i] = rec
            }
            rec = ""; pkg = ""
            return
        }
    }
    pkg_names[pkg_count] = pkg
    pkg_vers[pkg_count] = ver
    records[pkg_count] = rec
    pkg_count++
    rec = ""; pkg = ""
}
' Packages > Packages.tmp && mv Packages.tmp Packages
echo "       Packages generated (deduplicated)."

# ---- Step 2: 生成 depictions + 图标 + sileo-featured ----
CURRENT_STEP=$((CURRENT_STEP + 1))
echo "[$CURRENT_STEP/$TOTAL_STEPS] Generating depictions & icons..."

mkdir -p icon depictions
DEFAULT_ICON="icon/myicon.png"

# 预处理：收集所有包的文件状态信息，传递给 awk 以减少 system() 调用
STALE_COUNT=0
PKG_LIST=""
for deb in "$DEBS_DIR"/*.deb; do
    [ -f "$deb" ] || continue
    deb_name=$(basename "$deb")
    pkg_id="${deb_name%_*}"
    pkg_id="${pkg_id%_*}"
    dep_file="depictions/$pkg_id/info.json"
    icon_file="icon/$pkg_id.png"
    ss_dir="depictions/$pkg_id/screenshots"

    # 检查截图数量
    ss_count=0
    for i in 1 2 3 4 5 6 7 8 9 10; do
        [ -f "$ss_dir/$i.png" ] && ss_count=$i
    done

    # 检查 info.json 是否存在且版本是否匹配
    dep_exists=0
    dep_ver=""
    if [ -f "$dep_file" ]; then
        # 检查是否过期
        NEED_REGEN=false
        [ "$deb" -nt "$dep_file" ] && NEED_REGEN=true
        [ -d "$ss_dir" ] && [ "$(find "$ss_dir" -type f -newer "$dep_file" 2>/dev/null | head -1)" != "" ] && NEED_REGEN=true
        cl_file="depictions/$pkg_id/changelog.md"
        [ -f "$cl_file" ] && [ "$cl_file" -nt "$dep_file" ] && NEED_REGEN=true
        if [ "$NEED_REGEN" = true ]; then
            rm -f "$dep_file"
            STALE_COUNT=$((STALE_COUNT + 1))
        else
            dep_exists=1
            # 读取现有版本号
            dep_ver=$(grep '"版本", "text":' "$dep_file" 2>/dev/null | sed 's/.*"text": "//;s/".*//')
        fi
    fi

    # 图标是否存在
    icon_exists=0
    [ -f "$icon_file" ] && icon_exists=1

    # 默认图标是否存在
    default_icon_exists=0
    [ -f "$DEFAULT_ICON" ] && default_icon_exists=1

    PKG_LIST="$PKG_LIST $pkg_id|$dep_exists|$dep_ver|$ss_count|$icon_exists|$default_icon_exists"
done

if [ "$STALE_COUNT" -gt 0 ]; then
    echo "       过期 $STALE_COUNT 个"
fi

# 解析 Packages，为每个包生成 depiction JSON + 处理图标
awk -v url="$REPO_URL" -v defaultIcon="$DEFAULT_ICON" -v pkgList="$PKG_LIST" '
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
# 从预构建的 PKG_LIST 中查找包的状态
function getPkgState(pkgId, field) {
    n = split(pkgList, entries, " ")
    for (i = 1; i <= n; i++) {
        split(entries[i], fields, "|")
        if (fields[1] == pkgId) {
            return fields[field]
        }
    }
    return ""
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
    } else if ($0 ~ /^ / && desc != "") {
        line = substr($0, 2)
        desc = desc "\n" line
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

    # 从预构建状态读取
    pkgState_depExists = getPkgState(pkg, 2)
    pkgState_depVer = getPkgState(pkg, 3)
    pkgState_ssCount = getPkgState(pkg, 4) + 0
    pkgState_iconExists = getPkgState(pkg, 5)
    pkgState_defIconExists = getPkgState(pkg, 6)

    # info.json 已存在且版本一致 → 跳过
    if (pkgState_depExists == "1" && pkgState_depVer == version) {
        # 只处理图标
        if (pkgState_iconExists != "1" && pkgState_defIconExists == "1") {
            system("cp \"" defaultIcon "\" \"icon/" pkg ".png\"")
        }
        pkg = ""
        return
    }

    # 版本不一致 → 删除旧的 info.json，重新生成
    if (pkgState_depExists == "1") {
        system("rm -f \"" jFile "\"")
    }

    # 截图目录
    ss_dir = pDir "/screenshots"
    system("mkdir -p " ss_dir)
    ss_count = pkgState_ssCount

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
    print "        {" > jFile
    print "          \"class\": \"DepictionLayerView\"," > jFile
    print "          \"views\": [" > jFile
    print "            {\"text\": \"更新日志\", \"class\": \"DepictionLabelView\", \"fontWeight\": \"bold\", \"fontSize\": 16}" > jFile
    print "          ]" > jFile
    print "        }," > jFile
    printf "        {\"class\": \"DepictionMarkdownView\", \"markdown\": \"%s\"},\n", changelog > jFile
    print "        {\"class\": \"DepictionSeparatorView\"}" > jFile
    print "      ]" > jFile
    print "    }" > jFile
    print "  ]" > jFile
    print "}" > jFile
    close(jFile)

    # 图标：没有专属图标就用默认
    if (pkgState_iconExists != "1" && pkgState_defIconExists == "1") {
        system("cp \"" defaultIcon "\" \"icon/" pkg ".png\"")
        printf "       [图标] icon/%s.png (使用默认图标)\n", pkg
    }
    pkg = ""
}
' Packages

echo "       depictions & icons done."

# 清理孤立 depictions/icons（对应 debs 中已不存在的包）
echo "       (Checking for orphaned depictions/icons...)"
for dep_dir in depictions/*/; do
    [ -d "$dep_dir" ] || continue
    pkg_id=$(basename "$dep_dir")
    found=false
    # 通过 .cache 中的 Package 字段精准匹配（兼容非标准 deb 文件名）
    for cf in "$CACHE_DIR"/*.ctrl; do
        [ -f "$cf" ] || continue
        if grep -qi "^Package: $pkg_id$" "$cf" 2>/dev/null; then
            found=true
            break
        fi
    done
    if [ "$found" = false ]; then
        echo "       (清除孤立: depictions/$pkg_id)"
        rm -rf "$dep_dir"
        rm -f "icon/$pkg_id.png"
    fi
done

# ---- Step 3: 生成 sileo-featured.json ----
CURRENT_STEP=$((CURRENT_STEP + 1))
echo "[$CURRENT_STEP/$TOTAL_STEPS] Generating sileo-featured.json..."
awk '
BEGIN {
    print "{"
    print "  \"class\": \"FeatureView\","
    print "  \"tintColor\": \"#4A90D9\","
    print "  \"features\": ["
    print "    {"
    print "      \"class\": \"FeatureSection\","
    print "      \"title\": \"精选插件\","
    print "      \"features\": ["
    first = 1
}
/^Package: / {
    pkg = substr($0, index($0, ": ") + 2)
    if (!seen[pkg]++) {
        if (!first) print ","
        printf "        {\"class\": \"FeaturePackage\", \"package\": \"%s\"}", pkg
        first = 0
    }
}
END {
    print ""
    print "      ]"
    print "    }"
    print "  ]"
    print "}"
}
' Packages > sileo-featured.json
echo "       sileo-featured.json done ($(grep -c '"package"' sileo-featured.json) packages)."

# ---- Step 4: 并行压缩 Packages ----
CURRENT_STEP=$((CURRENT_STEP + 1))
echo "[$CURRENT_STEP/$TOTAL_STEPS] Compressing Packages (parallel)..."
COMPRESS_START=$(date +%s)

# 所有压缩任务并行执行
(bzip2 -fzk Packages 2>/dev/null; echo "       bz2 done") &
PID_BZ2=$!
(gzip -fk Packages 2>/dev/null; echo "       gz done") &
PID_GZ=$!
(xz -fzk Packages 2>/dev/null; echo "       xz done") &
PID_XZ=$!

PID_LZMA=""
if command -v lzma &>/dev/null; then
    (lzma -fzk Packages 2>/dev/null; echo "       lzma done") &
    PID_LZMA=$!
else
    echo "       (lzma not installed, skipped)"
fi

PID_ZST=""
if command -v zstd &>/dev/null; then
    (zstd -fk Packages 2>/dev/null; echo "       zst done") &
    PID_ZST=$!
else
    echo "       (zstd not installed, skipped)"
fi

# 等待所有压缩任务完成
wait $PID_BZ2 $PID_GZ $PID_XZ
[ -n "$PID_LZMA" ] && wait $PID_LZMA 2>/dev/null || true
[ -n "$PID_ZST" ] && wait $PID_ZST 2>/dev/null || true

COMPRESS_ELAPSED=$(($(date +%s) - COMPRESS_START))
echo "       并行压缩完成 (耗时 ${COMPRESS_ELAPSED}s)"

# ---- Step 5: 计算校验和 ----
CURRENT_STEP=$((CURRENT_STEP + 1))
echo "[$CURRENT_STEP/$TOTAL_STEPS] Calculating checksums..."

# 定义所有 Packages 变体
declare -a PACKAGE_FILES=("Packages")
declare -a COMPRESSED_FILES=()
for ext in bz2 gz xz lzma zst; do
    [ -f "Packages.$ext" ] && COMPRESSED_FILES+=("Packages.$ext")
done

# 一次性计算所有文件和算法，存入关联数组
declare -A CKSUM
for file in "Packages" "${COMPRESSED_FILES[@]}"; do
    CKSUM["$file|size"]=$(wc -c < "$file")
    CKSUM["$file|md5"]=$(md5sum "$file" | cut -d' ' -f1)
    CKSUM["$file|sha1"]=$(sha1sum "$file" | cut -d' ' -f1)
    CKSUM["$file|sha256"]=$(sha256sum "$file" | cut -d' ' -f1)
    CKSUM["$file|sha512"]=$(sha512sum "$file" | cut -d' ' -f1)
done

# ---- Step 6: 生成 Release 文件 ----
CURRENT_STEP=$((CURRENT_STEP + 1))
echo "[$CURRENT_STEP/$TOTAL_STEPS] Writing Release file..."

cat > Release <<EOF
Origin: $ORIGIN
Label: $LABEL
Suite: $SUITE
Version: 1.0
Codename: ios
Architectures: iphoneos-arm iphoneos-arm64 iphoneos-arm64e
Components: main
Description: $DESCRIPTION
Date: $(date -Ru)
EOF

# 用循环添加所有校验和（减少 200+ 行重复代码）
for algo in "MD5Sum" "SHA1" "SHA256" "SHA512"; do
    printf "\n%s:\n" "$algo" >> Release
    for file in "Packages" "${COMPRESSED_FILES[@]}"; do
        size="${CKSUM["$file|size"]}"
        case "$algo" in
            MD5Sum)  sum="${CKSUM["$file|md5"]}" ;;
            SHA1)    sum="${CKSUM["$file|sha1"]}" ;;
            SHA256)  sum="${CKSUM["$file|sha256"]}" ;;
            SHA512)  sum="${CKSUM["$file|sha512"]}" ;;
        esac
        printf " %s %s %s\n" "$sum" "$size" "$file" >> Release
    done
done

echo "       Release file written."

# 不覆盖 repo.conf 中的 DESCRIPTION（保留用户的设置）
# 但如果之前自动填充了，保存到配置文件持久化
if [ "$DESCRIPTION" != "无" ] && [ "$DESCRIPTION" != "" ]; then
    # 读取当前配置中的 DESCRIPTION
    CURRENT_DESC=$(grep "^DESCRIPTION=" "$REPO_CONFIG" 2>/dev/null | cut -d'"' -f2)
    if [ "$CURRENT_DESC" = "无" ] || [ "$CURRENT_DESC" = "" ]; then
        save_config 2>/dev/null || true
        echo "[i] DESCRIPTION 已持久化到 repo.conf"
    fi
fi

if [ "$DEPLOY_MODE" != "1" ]; then
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
fi
