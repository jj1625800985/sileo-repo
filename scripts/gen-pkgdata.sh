#!/bin/bash
#===============================================================
# gen-pkgdata.sh — 从 Packages 生成 packages.json
# 供 index.html 动态加载插件列表
#
# 用法: bash scripts/gen-pkgdata.sh
# 更新时自动调用: 集成在 update.sh 中
#===============================================================

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PKG_FILE="$ROOT_DIR/Packages"
OUTPUT="$ROOT_DIR/packages.json"

# ===== 精选插件列表（手动维护，新增插件按需添加） =====
FEATURED_PACKAGES=(
    "ai-config-gui"
    "claude-code-roothide"
    "com.dafei.terminal"
    "com.axs.ios16dao"
    "com.axs.switchicon"
    "com.wkk.zone"
    "com.Axs.stheno"
)

# ===== 检查输入文件 =====
if [ ! -f "$PKG_FILE" ]; then
    echo "[错误] 找不到 Packages 文件: $PKG_FILE"
    echo "    请先运行 update.sh 生成 Packages"
    exit 1
fi

echo "[生成] packages.json..."

# ===== awk 解析 Packages → JSON =====
# RS="" 模式：以空行分割记录，FS="\n" 使每个字段为一行
# 注意: $0 是整个记录(多行), 字段 $1..$NF 是每行内容
# 因此不能用 ^ 锚点匹配非首字段 — 改为遍历 NF 字段
awk -v featuredList="${FEATURED_PACKAGES[*]}" -v defaultSection="系统美化" '
BEGIN {
    split(featuredList, fArr)
    for (i in fArr) featuredPkgs[fArr[i]] = 1

    sectionMap["Development"] = "开发工具"
    sectionMap["Utilities"] = "开发工具"
    sectionMap["Tweaks"] = "系统美化"
    sectionMap["灵动岛"] = "灵动岛"
    sectionMap["分屏插件"] = "分屏插件"
    sectionMap["Terminal Support"] = "终端工具"
    sectionMap["System"] = "系统工具"

    RS = ""
    FS = "\n"
    first = 1
    print "["
}
{
    pkg = ""; name = ""; version = ""; section = ""; desc = ""

    # 遍历每条记录的每行字段
    for (i = 1; i <= NF; i++) {
        line = $i
        key = line
        sub(/:.*$/, "", key)
        val = line
        sub(/^[^:]+:[ \t]+/, "", val)

        if (key == "Package")  pkg = val
        if (key == "Name")     name = val
        if (key == "Version")  version = val
        if (key == "Section")  section = val
        if (key == "Description") {
            # 取第一行描述
            desc = val
        }
        if (key == "Description" || (key ~ /^[ \t]/ && desc != "")) {
            # Description 的续行
            gsub(/^[ \t]+/, "", line)
            if (line !~ /^[A-Z]/ || line !~ /:/) {
                # 续行不以大写字段名开头才追加
            }
        }
    }

    # 处理多行 Description
    desc = extractDesc()

    if (pkg == "" || version == "") next
    if (seen[pkg]++) next

    if (name == "") name = pkg

    cnSection = sectionMap[section]
    if (cnSection == "") cnSection = defaultSection

    isFeatured = (pkg in featuredPkgs) ? "true" : "false"

    # JSON 转义
    gsub(/"/, "\\\"", desc)
    gsub(/\\/, "\\\\", desc)
    gsub(/\t/, " ", desc)
    gsub(/\r/, "", desc)
    gsub(/\n+$/, "", desc)
    gsub(/\n/, "\\n", desc)

    gsub(/"/, "\\\"", name)
    gsub(/\\/, "\\\\", name)

    if (length(desc) > 200) desc = substr(desc, 1, 200) "…"

    if (first == 0) print ","
    first = 0

    printf "  {\n"
    printf "    \"id\": \"%s\",\n", pkg
    printf "    \"name\": \"%s\",\n", name
    printf "    \"version\": \"%s\",\n", version
    printf "    \"desc\": \"%s\",\n", desc
    printf "    \"section\": \"%s\",\n", cnSection
    printf "    \"featured\": %s\n", isFeatured
    printf "  }"
}
END {
    print ""
    print "]"
}
function extractDesc() {
    d = ""
    for (i = 1; i <= NF; i++) {
        if ($i ~ /^Description:/) {
            line = $i
            sub(/^Description:[ \t]+/, "", line)
            d = line
            # 后续续行
            for (j = i + 1; j <= NF; j++) {
                if ($j ~ /^[ \t]/) {
                    cline = $j
                    gsub(/^[ \t]+/, "", cline)
                    d = d "\n" cline
                } else {
                    break
                }
            }
            break
        }
    }
    gsub(/[ \t]+$/, "", d)
    return d
}
' "$PKG_FILE" > "$OUTPUT.tmp"

if [ $? -eq 0 ] && [ -s "$OUTPUT.tmp" ]; then
    mv "$OUTPUT.tmp" "$OUTPUT"
    PKG_COUNT=$(grep -c '"id":' "$OUTPUT")
    F_COUNT=$(grep -c '"featured": true' "$OUTPUT")
    echo "       packages.json 生成完毕: ${PKG_COUNT} 个包（精选 ${F_COUNT} 个）"
else
    echo "[警告] packages.json 生成失败，使用空数组"
    echo "[]" > "$OUTPUT"
fi
