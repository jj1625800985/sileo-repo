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

# ---- 颜色定义 ----
C_RESET="\033[0m"; C_BOLD="\033[1m"; C_DIM="\033[2m"
C_RED="\033[0;31m"; C_GREEN="\033[0;32m"; C_YELLOW="\033[0;33m"
C_BLUE="\033[0;34m"; C_PURPLE="\033[1;35m"; C_CYAN="\033[1;36m"
C_WHITE="\033[1;37m"; C_GRAY="\033[0;90m"
cecho() { local c="$1"; shift; echo -e "${c}$*${C_RESET}"; }
cprintf() { local c="$1"; shift; printf "${c}$*${C_RESET}"; }

# ---- 计时器 ----
SCRIPT_START=$(date +%s)
elapsed() { echo "$(($(date +%s) - SCRIPT_START))s"; }

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
DEFAULT_SUITE="stable"

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
        cecho "$C_GREEN" "[✓] 已加载配置: $REPO_CONFIG"
    else
        LABEL="$DEFAULT_LABEL"
        DESCRIPTION="$DEFAULT_DESCRIPTION"
        REPO_URL="$DEFAULT_REPO_URL"
        SUITE="$DEFAULT_SUITE"
        cecho "$C_YELLOW" "[!] 未找到配置文件，使用默认值"
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
    cecho "$C_GREEN" "[✓] 配置已保存: $REPO_CONFIG"
}

# ---- 交互式配置 ----
interactive_config() {
    echo ""
    cecho "$C_CYAN" "═══════════════════════════════════════════"
    cecho "$C_CYAN" "  仓库信息配置"
    cecho "$C_GRAY" "  留空则保持当前值不变"
    cecho "$C_CYAN" "═══════════════════════════════════════════"
    echo ""

    read -r -p "Origin  [$ORIGIN]: " input
    ORIGIN="${input:-$ORIGIN}"

    read -r -p "Label   [$LABEL]: " input
    LABEL="${input:-$LABEL}"

    read -r -p "Suite   [$SUITE]: " input
    SUITE="${input:-$SUITE}"

    echo -e "Description ${C_DIM}(当前: $DESCRIPTION)${C_RESET}"
    read -r -p "  新描述: " input
    DESCRIPTION="${input:-$DESCRIPTION}"

    read -r -p "Repo URL [$REPO_URL]: " input
    REPO_URL="${input:-$REPO_URL}"

    echo ""
    cecho "$C_CYAN" "═══════════════════════════════════════════"
    cecho "$C_CYAN" "  配置预览"
    cecho "$C_CYAN" "═══════════════════════════════════════════"
    echo -e "  ${C_DIM}Origin:${C_RESET}      $ORIGIN"
    echo -e "  ${C_DIM}Label:${C_RESET}       $LABEL"
    echo -e "  ${C_DIM}Suite:${C_RESET}       $SUITE"
    echo -e "  ${C_DIM}Description:${C_RESET} $DESCRIPTION"
    echo -e "  ${C_DIM}Repo URL:${C_RESET}    $REPO_URL"
    cecho "$C_CYAN" "═══════════════════════════════════════════"
    echo ""
    read -r -p "确认保存？(Y/n): " confirm
    case "$confirm" in
        n|N|no|NO) echo -e "  ${C_YELLOW}已取消${C_RESET}"; exit 0 ;;
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
                echo -e "  ${C_DIM}[i] DESCRIPTION 已自动更新为: $DESCRIPTION${C_RESET}"
            fi
        fi
    fi
}

# ---- 主流程开始 ----
cecho "$C_CYAN" ""
cecho "$C_CYAN" "╔═══════════════════════════════════════════╗"
cecho "$C_CYAN" "║        Sileo Repo Update v6.0            ║"
cecho "$C_CYAN" "╚═══════════════════════════════════════════╝"
cecho "$C_GRAY" "  路径: $ROOT_DIR"
cecho "$C_GRAY" "  时间: $(date '+%Y-%m-%d %H:%M:%S')"
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
TOTAL_STEPS=7
CURRENT_STEP=0

# 检查 debs 目录
DEB_COUNT=$(ls "$DEBS_DIR"/*.deb 2>/dev/null | wc -l)
if [ "$DEB_COUNT" -eq 0 ]; then
    echo -e "  ${C_RED}[!]${C_RESET} ${C_BOLD}debs/ 目录下没有 .deb 文件${C_RESET}"
    echo -e "  ${C_DIM}    请先将 .deb 放入 debs/ 目录${C_RESET}"
    echo ""
    exit 1
fi
echo -e "  ${C_PURPLE}▸${C_RESET} 检测到 ${C_BOLD}$DEB_COUNT${C_RESET} 个 .deb 包  ${C_GRAY}$(elapsed)${C_RESET}"
echo ""

# 修复之前可能由 sudo 留下的 root 权限文件（否则 awk 写入会失败）
for dir in depictions icon .cache; do
    if [ -d "$dir" ] && [ -n "$(find "$dir" -user root 2>/dev/null | head -1)" ]; then
        echo -e "  ${C_PURPLE}▸${C_RESET} 修复 ${C_YELLOW}$dir${C_RESET} 下 root 权限文件... ${C_GRAY}$(elapsed)${C_RESET}"
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
            echo -e "  ${C_DIM}清除过期缓存: $deb_name${C_RESET}"
        fi
    done
fi

# ---- Step 1: 生成 Packages（手动提取，支持所有压缩格式 + SHA512） ----
CURRENT_STEP=$((CURRENT_STEP + 1))
echo -e "\n  ${C_CYAN}═══════════════════════════════════════════${C_RESET}"
echo -e "  ${C_PURPLE}步骤 $CURRENT_STEP/$TOTAL_STEPS${C_RESET}: ${C_BOLD}生成 Packages${C_RESET}  ${C_GRAY}$(elapsed)${C_RESET}"
echo -e "  ${C_CYAN}═══════════════════════════════════════════${C_RESET}"

mkdir -p "$CACHE_DIR"
EXTRACTED=0
CACHED=0

echo -e "  ${C_BLUE}提取 deb 控制信息...${C_RESET}"
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
            # 从 deb 中提取 control（优先 dpkg-deb，无 ar 依赖）
            set +e
            CTRL_DATA=""
            # 方法1: dpkg-deb -f（iOS/APT 环境可用）
            if command -v dpkg-deb &>/dev/null; then
                CTRL_DATA=$(dpkg-deb -f "$deb" 2>/dev/null)
            fi
            # 方法2: 手动 ar 提取（传统方式，需 binutils）
            if [ -z "$CTRL_DATA" ]; then
                for ctrl in control.tar.zst control.tar.gz control.tar.xz control.tar; do
                    case "$ctrl" in
                        *.zst) CTRL_DATA=$(ar p "$deb" "$ctrl" 2>/dev/null | timeout 3 zstd -d 2>/dev/null | tar xO ./control 2>/dev/null) ;;
                        *.gz)  CTRL_DATA=$(ar p "$deb" "$ctrl" 2>/dev/null | tar xzO ./control 2>/dev/null) ;;
                        *.xz)  CTRL_DATA=$(ar p "$deb" "$ctrl" 2>/dev/null | tar xJO ./control 2>/dev/null) ;;
                        *)     CTRL_DATA=$(ar p "$deb" "$ctrl" 2>/dev/null | tar xO ./control 2>/dev/null) ;;
                    esac
                    if [ -n "$CTRL_DATA" ]; then break; fi
                done
            fi
            if [ -n "$CTRL_DATA" ]; then
                echo "$CTRL_DATA" > "$cache_file"
            fi
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
            echo "Filename: ./debs/$deb_name"
            echo "Size: $SIZE"
            echo "MD5sum: $MD5"
            echo "SHA1: $SHA1"
            echo "SHA256: $SHA256"
            echo "SHA512: $SHA512"
            echo ""
        fi
    done >> Packages
    echo -e "  ${C_GREEN}✓${C_RESET} 提取 ${C_BOLD}$EXTRACTED${C_RESET} 个，缓存命中 ${C_BOLD}$CACHED${C_RESET} 个  ${C_GRAY}$(elapsed)${C_RESET}"

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
/^[Ss]ileo[dD]epiction: / { needs_dep = 0; sub(/^[Ss]ileo[dD]epiction: /, "SileoDepiction: "); print; next }
/^[Ii]con: / { needs_icon = 0; sub(/^[Ii]con: /, "Icon: "); print; next }
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

# 保留所有版本：Sileo 列表按包名去重，但点进去可以看到所有版本可选
echo -e "  ${C_GREEN}✓${C_RESET} 保留所有版本（Sileo 多版本支持）  ${C_GRAY}$(elapsed)${C_RESET}"

# ---- Step 2: 生成 depictions + 图标 ----
CURRENT_STEP=$((CURRENT_STEP + 1))
echo -e "\n  ${C_CYAN}═══════════════════════════════════════════${C_RESET}"
echo -e "  ${C_PURPLE}步骤 $CURRENT_STEP/$TOTAL_STEPS${C_RESET}: ${C_BOLD}生成 Depictions & 图标${C_RESET}  ${C_GRAY}$(elapsed)${C_RESET}"
echo -e "  ${C_CYAN}═══════════════════════════════════════════${C_RESET}"

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
    echo -e "  ${C_YELLOW}过期 $STALE_COUNT 个${C_RESET}"
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

echo -e "  ${C_GREEN}✓${C_RESET} depictions & icons 已生成  ${C_GRAY}$(elapsed)${C_RESET}"

# 从原始插件 Icon URL 下载真实图标（替代通用 myicon.png）
echo -e "\n  ${C_BLUE}▸ 从外链下载原始图标...${C_RESET}"
DL_COUNT=0
DL_SKIP=0
DL_FAIL=0
for cf in "$CACHE_DIR"/*.ctrl; do
    [ -f "$cf" ] || continue
    pkg_id=$(grep "^Package:" "$cf" | head -1 | cut -d' ' -f2)
    icon_url=$(grep -i "^[Ii]con:" "$cf" | head -1 | cut -d' ' -f2-)
    [ -z "$icon_url" ] && { DL_SKIP=$((DL_SKIP + 1)); continue; }
    # 跳过 file:// 本地路径
    [[ "$icon_url" == file://* ]] && { DL_SKIP=$((DL_SKIP + 1)); continue; }
    # 跳过已经是本源的图标（避免回环下载）
    [[ "$icon_url" == *"jj1625800985.github.io"* ]] && { DL_SKIP=$((DL_SKIP + 1)); continue; }

    icon_file="icon/$pkg_id.png"
    # 如果图标已存在且不是 myicon.png（不同 blob），跳过
    if [ -f "$icon_file" ] && ! cmp -s "$icon_file" "$DEFAULT_ICON" 2>/dev/null; then
        DL_SKIP=$((DL_SKIP + 1))
        continue
    fi

    echo -e "  ${C_DIM}[下载]${C_RESET} $icon_url → $icon_file"
    if curl -sL --max-time 10 -o "$icon_file" "$icon_url" 2>/dev/null && [ -s "$icon_file" ]; then
        # 验证是真实图片
        if file "$icon_file" | grep -qi "PNG image data" 2>/dev/null; then
            DL_COUNT=$((DL_COUNT + 1))
            echo -e "  ${C_GREEN}[图标]${C_RESET} $icon_file ${C_DIM}(已下载原始图标)${C_RESET}"
        else
            # 下载内容不是图片，恢复默认
            cp "$DEFAULT_ICON" "$icon_file"
            DL_FAIL=$((DL_FAIL + 1))
        fi
    else
        # 下载失败，恢复默认
        [ -f "$DEFAULT_ICON" ] && cp "$DEFAULT_ICON" "$icon_file"
        DL_FAIL=$((DL_FAIL + 1))
    fi
done
echo -e "  ${C_GREEN}✓${C_RESET} 下载 ${C_BOLD}$DL_COUNT${C_RESET}，跳过 ${C_BOLD}$DL_SKIP${C_RESET}，失败 ${C_YELLOW}$DL_FAIL${C_RESET}  ${C_GRAY}$(elapsed)${C_RESET}"

# 从 deb 包内提取原始 app 图标（优先于外链下载）
echo -e "\n  ${C_BLUE}▸ 从 deb 内提取 App 图标...${C_RESET}"
EXTRACT_COUNT=0
EXTRACT_SKIP=0
for deb in "$DEBS_DIR"/*.deb; do
    [ -f "$deb" ] || continue
    deb_name=$(basename "$deb")
    pkg_id="${deb_name%_*}"; pkg_id="${pkg_id%_*}"
    icon_file="icon/$pkg_id.png"

    # 如果已有自定义图标（非默认），跳过
    if [ -f "$icon_file" ] && ! cmp -s "$icon_file" "$DEFAULT_ICON" 2>/dev/null; then
        EXTRACT_SKIP=$((EXTRACT_SKIP + 1))
        continue
    fi

    # 查找 deb 内 app 图标（优先 AppIcon60x60@2x.png）
    app_icon=$(dpkg-deb -c "$deb" 2>/dev/null | grep -oP '\.app/AppIcon(60x60@2x|60x60|).*\.\Kpng' | head -1)
    [ -z "$app_icon" ] && { EXTRACT_SKIP=$((EXTRACT_SKIP + 1)); continue; }

    # 提取具体路径
    icon_path=$(dpkg-deb -c "$deb" 2>/dev/null | grep -oP '/Applications/.*?AppIcon[^ ]*\.png' | head -1)
    [ -z "$icon_path" ] && { EXTRACT_SKIP=$((EXTRACT_SKIP + 1)); continue; }

    if dpkg-deb --fsys-tarfile "$deb" 2>/dev/null | tar xO ".$icon_path" > "$icon_file" 2>/dev/null; then
        if file "$icon_file" | grep -qi "PNG image data" 2>/dev/null; then
            echo -e "  ${C_GREEN}[提取]${C_RESET} $icon_file ${C_DIM}← $icon_path${C_RESET}"
            EXTRACT_COUNT=$((EXTRACT_COUNT + 1))
        else
            rm -f "$icon_file"
            EXTRACT_SKIP=$((EXTRACT_SKIP + 1))
        fi
    else
        EXTRACT_SKIP=$((EXTRACT_SKIP + 1))
    fi
done
echo -e "  ${C_GREEN}✓${C_RESET} 提取 ${C_BOLD}$EXTRACT_COUNT${C_RESET} 个，跳过 ${C_BOLD}$EXTRACT_SKIP${C_RESET} 个  ${C_GRAY}$(elapsed)${C_RESET}"

# 验证所有图标是否是真正的 PNG（修复 JPEG 伪装问题）
echo -e "\n  ${C_BLUE}▸ 验证图标格式...${C_RESET}"
PNG_FIXED=0
for icon_f in icon/*.png; do
    [ -f "$icon_f" ] || continue
    if ! file "$icon_f" | grep -qi "PNG image data" 2>/dev/null; then
        # 不是真 PNG，替换为默认图标
        if [ -f "$DEFAULT_ICON" ]; then
            cp "$DEFAULT_ICON" "$icon_f"
            PNG_FIXED=$((PNG_FIXED + 1))
            echo -e "  ${C_YELLOW}[修复]${C_RESET} $icon_f ${C_DIM}(非 PNG，替换为默认图标)${C_RESET}"
        fi
    fi
done
[ "$PNG_FIXED" -gt 0 ] && echo -e "  ${C_GREEN}✓${C_RESET} 修复 ${C_YELLOW}$PNG_FIXED${C_RESET} 个非 PNG 图标  ${C_GRAY}$(elapsed)${C_RESET}"
[ "$PNG_FIXED" -eq 0 ] && echo -e "  ${C_GREEN}✓${C_RESET} 所有图标均为 PNG 格式  ${C_GRAY}$(elapsed)${C_RESET}"

# 清理孤立 depictions/icons（对应 debs 中已不存在的包）
echo -e "\n  ${C_BLUE}▸ 清理孤立 depictions/icons...${C_RESET}"
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
        echo -e "  ${C_DIM}[清除]${C_RESET} depictions/$pkg_id"
        rm -rf "$dep_dir"
        rm -f "icon/$pkg_id.png"
    fi
done
echo -e "  ${C_GREEN}✓${C_RESET} 孤立检查完成  ${C_GRAY}$(elapsed)${C_RESET}"

# ---- Step 3: 生成 sileo-featured.json（FeaturedBannersView 轮播横幅格式） ----
CURRENT_STEP=$((CURRENT_STEP + 1))
echo -e "\n  ${C_CYAN}═══════════════════════════════════════════${C_RESET}"
echo -e "  ${C_PURPLE}步骤 $CURRENT_STEP/$TOTAL_STEPS${C_RESET}: ${C_BOLD}生成 sileo-featured.json${C_RESET}  ${C_GRAY}$(elapsed)${C_RESET}"
echo -e "  ${C_CYAN}═══════════════════════════════════════════${C_RESET}"
awk -v url="$REPO_URL" '
BEGIN {
    print "{"
    print "  \"class\": \"FeaturedBannersView\","
    print "  \"itemSize\": \"{390, 190}\","
    print "  \"itemCornerRadius\": 10,"
    print "  \"banners\": ["
    first = 1
    bannerIdx = 0
}
/^Package: / {
    pkg = substr($0, index($0, ": ") + 2)
    if (!seen[pkg]++ && bannerIdx < 5) {
        if (!first) print ","
        first = 0
        bannerIdx++
        printf "    {\"url\": \"%s/icon/%s.png\", \"title\": \"\", \"package\": \"%s\", \"hideShadow\": false}", url, pkg, pkg
    }
}
END {
    print ""
    print "  ]"
    print "}"
}
' Packages > sileo-featured.json
BANNER_COUNT=$(grep -c '"package"' sileo-featured.json)
echo -e "  ${C_GREEN}✓${C_RESET} sileo-featured.json ${C_DIM}(${C_RESET}${C_BOLD}$BANNER_COUNT${C_RESET}${C_DIM} banners)${C_RESET}  ${C_GRAY}$(elapsed)${C_RESET}"

# ---- Step 4: 并行压缩 Packages ----
CURRENT_STEP=$((CURRENT_STEP + 1))
echo -e "\n  ${C_CYAN}═══════════════════════════════════════════${C_RESET}"
echo -e "  ${C_PURPLE}步骤 $CURRENT_STEP/$TOTAL_STEPS${C_RESET}: ${C_BOLD}并行压缩 Packages${C_RESET}  ${C_GRAY}$(elapsed)${C_RESET}"
echo -e "  ${C_CYAN}═══════════════════════════════════════════${C_RESET}"
COMPRESS_START=$(date +%s)

# 所有压缩任务并行执行
(bzip2 -fzk Packages 2>/dev/null; echo -e "  ${C_DIM}bzip2${C_RESET} ${C_GREEN}✓${C_RESET}") &
PID_BZ2=$!
(gzip -fk Packages 2>/dev/null; echo -e "  ${C_DIM}gzip${C_RESET} ${C_GREEN}✓${C_RESET}") &
PID_GZ=$!
(xz -fzk Packages 2>/dev/null; echo -e "  ${C_DIM}xz${C_RESET} ${C_GREEN}✓${C_RESET}") &
PID_XZ=$!

PID_LZMA=""
if command -v lzma &>/dev/null; then
    (lzma -fzk Packages 2>/dev/null; echo -e "  ${C_DIM}lzma${C_RESET} ${C_GREEN}✓${C_RESET}") &
    PID_LZMA=$!
else
    echo -e "  ${C_DIM}lzma${C_RESET} ${C_YELLOW}未安装，跳过${C_RESET}"
fi

PID_ZST=""
if command -v zstd &>/dev/null; then
    (zstd -fk Packages 2>/dev/null; echo -e "  ${C_DIM}zstd${C_RESET} ${C_GREEN}✓${C_RESET}") &
    PID_ZST=$!
else
    echo -e "  ${C_DIM}zstd${C_RESET} ${C_YELLOW}未安装，跳过${C_RESET}"
fi

# 等待所有压缩任务完成
wait $PID_BZ2 $PID_GZ $PID_XZ
[ -n "$PID_LZMA" ] && wait $PID_LZMA 2>/dev/null || true
[ -n "$PID_ZST" ] && wait $PID_ZST 2>/dev/null || true

COMPRESS_ELAPSED=$(($(date +%s) - COMPRESS_START))
echo -e "  ${C_GREEN}✓${C_RESET} 并行压缩完成 ${C_DIM}(${C_RESET}${COMPRESS_ELAPSED}s${C_DIM})${C_RESET}  ${C_GRAY}$(elapsed)${C_RESET}"

# ---- Step 5: 计算校验和 ----
CURRENT_STEP=$((CURRENT_STEP + 1))
echo -e "\n  ${C_CYAN}═══════════════════════════════════════════${C_RESET}"
echo -e "  ${C_PURPLE}步骤 $CURRENT_STEP/$TOTAL_STEPS${C_RESET}: ${C_BOLD}计算校验和${C_RESET}  ${C_GRAY}$(elapsed)${C_RESET}"
echo -e "  ${C_CYAN}═══════════════════════════════════════════${C_RESET}"

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
echo -e "  ${C_GREEN}✓${C_RESET} 校验和计算完成 ${C_DIM}(${C_RESET}${#COMPRESSED_FILES[@]} 个压缩文件${C_DIM})${C_RESET}  ${C_GRAY}$(elapsed)${C_RESET}"

# ---- Step 6: 生成 Release 文件 ----
CURRENT_STEP=$((CURRENT_STEP + 1))
echo -e "\n  ${C_CYAN}═══════════════════════════════════════════${C_RESET}"
echo -e "  ${C_PURPLE}步骤 $CURRENT_STEP/$TOTAL_STEPS${C_RESET}: ${C_BOLD}生成 Release 文件${C_RESET}  ${C_GRAY}$(elapsed)${C_RESET}"
echo -e "  ${C_CYAN}═══════════════════════════════════════════${C_RESET}"

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

echo -e "  ${C_GREEN}✓${C_RESET} Release 文件已生成  ${C_GRAY}$(elapsed)${C_RESET}"

# ---- Step 7: 生成 packages.json（供 index.html 动态加载） ----
CURRENT_STEP=$((CURRENT_STEP + 1))
echo -e "\n  ${C_CYAN}═══════════════════════════════════════════${C_RESET}"
echo -e "  ${C_PURPLE}步骤 $CURRENT_STEP/$TOTAL_STEPS${C_RESET}: ${C_BOLD}生成 packages.json${C_RESET}  ${C_GRAY}$(elapsed)${C_RESET}"
echo -e "  ${C_CYAN}═══════════════════════════════════════════${C_RESET}"
bash "$ROOT_DIR/scripts/gen-pkgdata.sh"
echo -e "  ${C_GREEN}✓${C_RESET} packages.json 已生成  ${C_GRAY}$(elapsed)${C_RESET}"

# 更新 TOTAL_STEPS
TOTAL_STEPS=$((TOTAL_STEPS + 1))

# 不覆盖 repo.conf 中的 DESCRIPTION（保留用户的设置）
# 但如果之前自动填充了，保存到配置文件持久化
if [ "$DESCRIPTION" != "无" ] && [ "$DESCRIPTION" != "" ]; then
    # 读取当前配置中的 DESCRIPTION
    CURRENT_DESC=$(grep "^DESCRIPTION=" "$REPO_CONFIG" 2>/dev/null | cut -d'"' -f2)
    if [ "$CURRENT_DESC" = "无" ] || [ "$CURRENT_DESC" = "" ]; then
        save_config 2>/dev/null || true
        echo -e "  ${C_DIM}[i] DESCRIPTION 已持久化到 repo.conf${C_RESET}"
    fi
fi

if [ "$DEPLOY_MODE" != "1" ]; then
TOTAL_ELAPSED=$(elapsed)
echo ""
cecho "$C_CYAN" "╔═══════════════════════════════════════════╗"
cecho "$C_CYAN" "║           更新完成！                      ║"
cecho "$C_CYAN" "╚═══════════════════════════════════════════╝"
echo -e "  ${C_GRAY}耗时: ${C_BOLD}$TOTAL_ELAPSED${C_RESET}"
echo ""
cecho "$C_BOLD" "  仓库就绪:"
echo -e "  ${C_CYAN}▸${C_RESET} ${C_DIM}路径:${C_RESET}  $ROOT_DIR"
echo ""
cecho "$C_BOLD" "  Sileo 显示:"
echo -e "  ${C_CYAN}▸${C_RESET} ${C_DIM}源名称:${C_RESET}  ${C_YELLOW}$LABEL${C_RESET}"
echo -e "  ${C_CYAN}▸${C_RESET} ${C_DIM}描述:${C_RESET}    $DESCRIPTION"
echo -e "  ${C_CYAN}▸${C_RESET} ${C_DIM}地址:${C_RESET}    ${C_BLUE}$REPO_URL${C_RESET}"
echo ""
cecho "$C_BOLD"  " 后续步骤:"
cecho "$C_DIM"   "   1. 添加 .deb 文件到 debs/"
cecho "$C_DIM"   "   2. 运行 ./scripts/update.sh"
cecho "$C_DIM"   "   3. Commit & push 到 GitHub"
cecho "$C_DIM"   "   4. 启用 GitHub Pages (main branch, /root)"
cecho "$C_DIM"   "   5. 在 Sileo 中添加源:"
echo -e "      ${C_BLUE}$REPO_URL${C_RESET}"
echo ""
fi
