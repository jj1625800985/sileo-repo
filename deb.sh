#!/bin/bash
#===============================================================
# .deb 解包/重包工具（智能交互版）
# 用法:
#   ./deb.sh                    # 交互菜单
#   ./deb.sh extract xxx.deb    # 解包
#   ./deb.sh pack   xxx.deb     # 重打包
#   ./deb.sh edit   xxx.deb     # 解包 → 直接打开 control 编辑
#   ./deb.sh deploy             # 解包 → 改 → 重包 → 部署一条龙
#===============================================================
set -e

WORKDIR="/tmp/deb_work"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEBS_DIR="$SCRIPT_DIR/debs"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  .deb 处理工具${NC}"
echo -e "${BLUE}========================================${NC}"

# ============================================================
# 辅助函数
# ============================================================

# 列出 debs/ 目录下的所有 deb，带编号
list_debs() {
    local debs=("$DEBS_DIR"/*.deb 2>/dev/null)
    if [ ! -d "$DEBS_DIR" ] || [ ${#debs[@]} -eq 0 ] || [ ! -f "${debs[0]}" ]; then
        echo ""
        return 1
    fi
    echo -e "${YELLOW}debs/ 目录下的可用包:${NC}"
    local i=1
    for f in "$DEBS_DIR"/*.deb; do
        [ -f "$f" ] || continue
        local name=$(basename "$f")
        local pkg=$(tar -xf "$(ar t "$f" 2>/dev/null | grep control)" -O 2>/dev/null | grep "^Package:" | head -1 | sed 's/Package: //' 2>/dev/null || echo "?")
        printf "  %2d) %s\n" "$i" "$name"
        i=$((i+1))
    done
    echo ""
    return 0
}

# 通过编号或关键词查找 deb 文件
find_deb() {
    local input="$1"

    # 如果直接是文件路径且存在
    if [ -f "$input" ]; then
        echo "$input"
        return 0
    fi

    # 如果是纯数字（编号）
    if [[ "$input" =~ ^[0-9]+$ ]]; then
        local i=1
        for f in "$DEBS_DIR"/*.deb; do
            [ -f "$f" ] || continue
            if [ "$i" -eq "$input" ]; then
                echo "$f"
                return 0
            fi
            i=$((i+1))
        done
    fi

    # 关键词匹配
    local matches=()
    for f in "$DEBS_DIR"/*.deb; do
        [ -f "$f" ] || continue
        if [[ "$(basename "$f")" == *"$input"* ]]; then
            matches+=("$f")
        fi
    done

    if [ ${#matches[@]} -eq 1 ]; then
        echo "${matches[0]}"
        return 0
    elif [ ${#matches[@]} -gt 1 ]; then
        echo -e "${YELLOW}匹配到多个文件:${NC}"
        local i=1
        for f in "${matches[@]}"; do
            printf "  %d) %s\n" "$i" "$(basename "$f")"
            i=$((i+1))
        done
        echo ""
        read -p "输编号选择: " sel
        if [[ "$sel" =~ ^[0-9]+$ ]] && [ "$sel" -ge 1 ] && [ "$sel" -le "${#matches[@]}" ]; then
            echo "${matches[$((sel-1))]}"
            return 0
        fi
    fi

    echo ""
    return 1
}

# 显示 control 内容
show_control() {
    local ctrl_file="$WORKDIR/control/control"
    if [ -f "$ctrl_file" ]; then
        echo -e "${YELLOW}=== 当前 control 内容 ===${NC}"
        cat "$ctrl_file"
        echo -e "${YELLOW}=========================${NC}"
    fi
}

# 显示 data 文件树
show_data_tree() {
    echo -e "${YELLOW}=== data 文件列表 ===${NC}"
    find "$WORKDIR/data" -type f -o -type d | sort | sed "s|$WORKDIR/data||" | head -40
    local count=$(find "$WORKDIR/data" -type f | wc -l)
    echo -e "${YELLOW}共 $count 个文件${NC}"
}

# ============================================================
# 主功能
# ============================================================

# 解包
do_extract() {
    local deb_file="$1"

    if [ ! -f "$deb_file" ]; then
        echo -e "${YELLOW}[!] 文件不存在: $deb_file${NC}"
        return 1
    fi

    # 如果工作目录存在，询问是否覆盖
    if [ -d "$WORKDIR" ]; then
        read -p "工作目录已存在，覆盖？(y/n): " yn
        [[ "$yn" != "y" ]] && echo "已取消" && return 0
    fi

    rm -rf "$WORKDIR"
    mkdir -p "$WORKDIR/control" "$WORKDIR/data"

    local deb_name=$(basename "$deb_file")
    cp "$deb_file" "$WORKDIR/"

    cd "$WORKDIR"
    ar x "$deb_name"

    # 解压 control
    cd control
    tar xf ../control.tar.xz 2>/dev/null || tar xf ../control.tar.gz 2>/dev/null || tar xf ../control.tar.zst 2>/dev/null || true

    echo ""
    show_control

    # 解压 data
    cd "$WORKDIR/data"
    tar xf ../data.tar.xz 2>/dev/null || tar xf ../data.tar.gz 2>/dev/null || tar xf ../data.tar.zst 2>/dev/null || true

    echo ""
    show_data_tree

    DEB_NAME="$deb_name"
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN} 解包完成！${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "  control 文件: $WORKDIR/control/"
    echo "  插件文件目录: $WORKDIR/data/"
    echo ""
    echo -e "  ${YELLOW}常用操作:${NC}"
    echo "    vi $WORKDIR/control/control        ← 改包名/版本/描述"
    echo "    vi $WORKDIR/data/...               ← 改插件文件"
    echo "    sed -i 's/旧/com.sxllm.新/g' ...  ← 批量替换字符串"
    echo "    find $WORKDIR/data -type f         ← 查看所有文件"
    echo ""

    # 交互菜单
    while true; do
        echo "  1) 编辑 control 文件"
        echo "  2) 查看 data 目录结构"
        echo "  3) 显示 control 内容"
        echo "  4) 重打包"
        echo "  5) 重打包并部署 (deploy)"
        echo "  0) 退出"
        read -p "  选择 [0-5]: " action

        case "$action" in
            1)
                if command -v vi &>/dev/null; then
                    vi "$WORKDIR/control/control"
                    echo ""
                    show_control
                elif command -v vim &>/dev/null; then
                    vim "$WORKDIR/control/control"
                else
                    echo -e "${YELLOW}没有找到 vi，请手动编辑:${NC}"
                    echo "  $WORKDIR/control/control"
                fi
                ;;
            2)
                show_data_tree
                echo ""
                read -p "按 Enter 继续" _
                ;;
            3)
                show_control
                echo ""
                read -p "按 Enter 继续" _
                ;;
            4)
                do_pack "$deb_file"
                break
                ;;
            5)
                do_pack "$deb_file"
                # 自动部署
                if [ -f "$SCRIPT_DIR/deploy.sh" ]; then
                    echo ""
                    read -p "是否运行 deploy.sh 推送源？(y/n): " do_deploy
                    if [ "$do_deploy" = "y" ]; then
                        cd "$SCRIPT_DIR"
                        bash deploy.sh
                    fi
                fi
                break
                ;;
            0)
                echo "退出，工作目录保留在: $WORKDIR"
                break
                ;;
        esac
    done
}

# 重打包
do_pack() {
    local deb_file="$1"

    if [ ! -d "$WORKDIR" ] || [ ! -d "$WORKDIR/control" ]; then
        echo -e "${YELLOW}[!] 没有找到解包内容，请先运行 extract${NC}"
        return 1
    fi

    cd "$WORKDIR"

    # 检测压缩格式
    local ctrl_ext="xz" data_ext="xz"
    for f in control.tar.*; do
        [ -f "$f" ] && ctrl_ext="${f##*.}" && break
    done
    for f in data.tar.*; do
        [ -f "$f" ] && data_ext="${f##*.}" && break
    done

    # 重打包
    cd control
    tar caf "../control.tar.$ctrl_ext" *
    cd "$WORKDIR"

    cd data
    tar caf "../data.tar.$data_ext" *
    cd "$WORKDIR"

    local new_deb="$(basename "$deb_file")"
    ar rcs "$new_deb" debian-binary "control.tar.$ctrl_ext" "data.tar.$data_ext"
    cp "$new_deb" "$deb_file"

    local size=$(du -h "$deb_file" | cut -f1)

    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN} 打包完成！${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "  已更新: $deb_file"
    echo "  大小: $size"
    echo ""

    rm -rf "$WORKDIR"
}

# 交互菜单
interactive_menu() {
    echo ""

    # 检查是否有 debs 目录
    if ! list_debs; then
        echo -e "${YELLOW}debs/ 目录下没有 .deb 文件${NC}"
        echo "请先将 .deb 文件放入 $DEBS_DIR"
        exit 1
    fi

    # 检测是否已有解包的工作目录
    local has_workdir=0
    if [ -d "$WORKDIR/control" ] && [ -f "$WORKDIR/control/control" ]; then
        has_workdir=1
    fi

    echo "  1) 解包 (extract)"
    echo "  2) 解包并编辑 (edit)"
    if [ "$has_workdir" -eq 1 ]; then
        echo "  3) 继续编辑 (工作目录存在)"
        echo "  4) 重打包 (pack)"
    fi
    echo "  5) 重打包并部署"
    echo "  0) 退出"
    echo ""
    read -p "选择: " choice

    case "$choice" in
        1)
            list_debs
            read -p "输编号或关键词: " sel
            local f=$(find_deb "$sel")
            if [ -n "$f" ]; then
                do_extract "$f"
            else
                echo -e "${YELLOW}没找到匹配的 deb 文件${NC}"
            fi
            ;;
        2)
            list_debs
            read -p "输编号或关键词: " sel
            local f=$(find_deb "$sel")
            if [ -n "$f" ]; then
                do_extract "$f"
                # 自动打开 control 编辑
                if [ -f "$WORKDIR/control/control" ]; then
                    if command -v vi &>/dev/null; then
                        echo ""
                        read -p "按 Enter 打开 control 编辑..." _
                        vi "$WORKDIR/control/control"
                        show_control
                    fi
                fi
            else
                echo -e "${YELLOW}没找到匹配的 deb 文件${NC}"
            fi
            ;;
        3)
            if [ "$has_workdir" -eq 1 ]; then
                show_control
                echo ""
                show_data_tree
                echo ""
                echo "工作目录: $WORKDIR"
                echo "输入 vi $WORKDIR/control/control 编辑"
            else
                echo -e "${YELLOW}没有找到解包的工作目录${NC}"
            fi
            ;;
        4|5)
            if [ "$has_workdir" -eq 1 ]; then
                # 尝试从工作目录推断原 deb 路径
                local deb_path=$(ls "$WORKDIR"/*.deb 2>/dev/null | head -1)
                if [ -n "$deb_path" ]; then
                    local target="$DEBS_DIR/$(basename "$deb_path")"
                    do_pack "$target"
                    if [ "$choice" -eq 5 ] && [ -f "$SCRIPT_DIR/deploy.sh" ]; then
                        read -p "是否运行 deploy.sh？(y/n): " dd
                        [ "$dd" = "y" ] && cd "$SCRIPT_DIR" && bash deploy.sh
                    fi
                else
                    echo -e "${YELLOW}找不到原 deb 文件，请指定路径${NC}"
                    read -p "输入 .deb 文件路径: " manual_path
                    [ -n "$manual_path" ] && do_pack "$manual_path"
                fi
            else
                echo -e "${YELLOW}没有找到解包的工作目录${NC}"
            fi
            ;;
        0)
            exit 0
            ;;
    esac
}

# ============================================================
# 入口
# ============================================================

CMD=$1

case "$CMD" in
    extract)
        F=$(find_deb "$2") && [ -n "$F" ] && do_extract "$F" || { echo -e "${YELLOW}用法: $0 extract <编号/关键词/文件路径>${NC}"; list_debs; }
        ;;
    pack)
        F=$(find_deb "$2")
        if [ -n "$F" ]; then
            do_pack "$F"
        else
            # 可能工作目录里有
            local deb_path=$(ls "$WORKDIR"/*.deb 2>/dev/null | head -1)
            if [ -n "$deb_path" ]; then
                do_pack "$DEBS_DIR/$(basename "$deb_path")"
            else
                echo -e "${YELLOW}用法: $0 pack <编号/关键词/文件路径>${NC}"
            fi
        fi
        ;;
    edit)
        F=$(find_deb "$2") && [ -n "$F" ] && do_extract "$F" || true
        if [ -f "$WORKDIR/control/control" ] && command -v vi &>/dev/null; then
            vi "$WORKDIR/control/control"
            show_control
        fi
        ;;
    deploy)
        # 全自动：解包 → 提示编辑 → 重包 → 部署
        F=$(find_deb "$2")
        [ -z "$F" ] && { echo -e "${YELLOW}用法: $0 deploy <编号/关键词>${NC}"; list_debs; exit 1; }
        do_extract "$F"
        echo ""
        read -p "编辑完成后，按 Enter 重打包..." _
        do_pack "$F"
        if [ -f "$SCRIPT_DIR/deploy.sh" ]; then
            echo ""
            read -p "运行 deploy.sh 推送源？(y/n): " dd
            [ "$dd" = "y" ] && cd "$SCRIPT_DIR" && bash deploy.sh
        fi
        ;;
    "")
        interactive_menu
        ;;
    *)
        echo -e "${YELLOW}未知命令: $CMD${NC}"
        echo "可用命令: extract, pack, edit, deploy"
        ;;
esac
