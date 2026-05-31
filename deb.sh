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
    if [ ! -d "$DEBS_DIR" ]; then
        echo ""
        return 1
    fi
    # 检查是否有 .deb 文件
    local has_deb=0
    for f in "$DEBS_DIR"/*.deb; do
        [ -f "$f" ] && has_deb=1 && break
    done
    if [ "$has_deb" -eq 0 ]; then
        echo ""
        return 1
    fi
    echo -e "${YELLOW}debs/ 目录下的可用包:${NC}"
    local i=1
    for f in "$DEBS_DIR"/*.deb; do
        [ -f "$f" ] || continue
        local name=$(basename "$f")
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

    # 如果工作目录存在，先处理权限再删除
    if [ -d "$WORKDIR" ]; then
        read -p "工作目录已存在，覆盖？(y/n): " yn
        [[ "$yn" != "y" ]] && echo "已取消" && return 0
        chmod -R 777 "$WORKDIR" 2>/dev/null || true
        rm -rf "$WORKDIR" 2>/dev/null || {
            echo -e "${YELLOW}[!] 权限不足，尝试 sudo 删除...${NC}"
            sudo rm -rf "$WORKDIR" 2>/dev/null || {
                echo -e "${YELLOW}[!] 删除失败，换个工作目录...${NC}"
                WORKDIR="/tmp/deb_work_$$"
                echo "  新目录: $WORKDIR"
            }
        }
    fi

    rm -rf "$WORKDIR"
    mkdir -p "$WORKDIR/control" "$WORKDIR/data"

    local deb_name=$(basename "$deb_file")
    cp "$deb_file" "$WORKDIR/"

    # 解压 tar 文件（支持多种压缩格式）
    extract_tar() {
        local src="$1" dest="$2"
        mkdir -p "$dest"
        if tar xf "$src" -C "$dest" 2>/dev/null; then return 0; fi
        if xz -dc "$src" 2>/dev/null | tar xf - -C "$dest" 2>/dev/null; then return 0; fi
        if zstd -dc "$src" 2>/dev/null | tar xf - -C "$dest" 2>/dev/null; then return 0; fi
        if gzip -dc "$src" 2>/dev/null | tar xf - -C "$dest" 2>/dev/null; then return 0; fi
        if bzip2 -dc "$src" 2>/dev/null | tar xf - -C "$dest" 2>/dev/null; then return 0; fi
        if lzma -dc "$src" 2>/dev/null | tar xf - -C "$dest" 2>/dev/null; then return 0; fi
        return 1
    }

    cd "$WORKDIR"
    ar x "$deb_name"

    # 解压 control
    extract_tar "control.tar.xz" "control" || \
    extract_tar "control.tar.gz" "control" || \
    extract_tar "control.tar.zst" "control" || \
    { for f in control.tar.*; do [ -f "$f" ] && extract_tar "$f" "control" && break; done; }

    echo ""
    show_control
    if [ ! -f "$WORKDIR/control/control" ]; then
        echo -e "${YELLOW}[!] 警告: control 文件未解压成功${NC}"
        echo "工作目录: $WORKDIR"
        ls -la "$WORKDIR/control/"
    fi

    # 解压 data
    extract_tar "data.tar.xz" "data" || \
    extract_tar "data.tar.gz" "data" || \
    extract_tar "data.tar.zst" "data" || \
    { for f in data.tar.*; do [ -f "$f" ] && extract_tar "$f" "data" && break; done; }

    echo ""
    show_data_tree

    DEB_NAME="$deb_name"
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN} 解包完成！（已进入工作目录）${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "  ${YELLOW}快捷操作:${NC}"
    echo "    vi control/control         改包名/版本/描述"
    echo "    vi data/...                改插件文件"
    echo "    find data -type f          查看所有文件"
    echo "    sed -i 's/旧/新/g' data/..  批量替换"
    echo ""

    cd "$WORKDIR"

    # 交互菜单
    while true; do
        echo "  1) 编辑 control 文件"
        echo "  2) 查看 data 目录结构"
        echo "  3) 显示 control 内容"
        echo "  4) 重打包"
        echo "  5) 重打包并部署 (deploy)"
        echo "  6) 进入工作目录操作（用完输 exit 返回）"
        echo "  0) 退出"
        read -p "  选择 [0-5]: " action

        case "$action" in
            1)
                local ctrl="$WORKDIR/control/control"
                while true; do
                    clear 2>/dev/null || true
                    echo ""
                    echo -e "${YELLOW}=== 修改 control 字段（选编号改值）===${NC}"
                    echo ""

                    # 读取所有字段到数组
                    local f_keys=() f_vals=()
                    while IFS=': ' read -r key val; do
                        [ -z "$key" ] && continue
                        f_keys+=("$key")
                        f_vals+=("$val")
                    done < "$ctrl"

                    local i=1
                    for idx in "${!f_keys[@]}"; do
                        printf "  %2d) %s = ${GREEN}%s${NC}\n" "$i" "${f_keys[$idx]}" "${f_vals[$idx]}"
                        i=$((i+1))
                    done
                    echo ""
                    echo "  s) 显示原始文件内容"
                    echo "  q) 返回菜单"
                    echo ""
                    read -p "  选择: " sel

                    case "$sel" in
                        q) break ;;
                        s)
                            cat "$ctrl"
                            echo ""
                            read -p "  按 Enter 继续" _
                            ;;
                        *)
                            if [[ "$sel" =~ ^[0-9]+$ ]] && [ "$sel" -ge 1 ] && [ "$sel" -le "${#f_keys[@]}" ]; then
                                local idx=$((sel-1))
                                echo ""
                                echo "  字段: ${f_keys[$idx]}"
                                echo "  当前值: ${f_vals[$idx]}"
                                read -p "  新值（直接回车=不变）: " new_val
                                if [ -n "$new_val" ]; then
                                    sed -i "s|^${f_keys[$idx]}: .*|${f_keys[$idx]}: $new_val|" "$ctrl"
                                    echo -e "${GREEN}  已更新！${NC}"
                                else
                                    echo "  未修改"
                                fi
                                read -p "  按 Enter 继续" _
                            fi
                            ;;
                    esac
                done
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
            6)
                echo ""
                echo -e "${GREEN}已进入工作目录，操作完输 exit 返回菜单${NC}"
                echo -e "${YELLOW}  vi control/control         改包名${NC}"
                echo -e "${YELLOW}  vi data/...                改文件${NC}"
                echo -e "${YELLOW}  find data -type f          看文件列表${NC}"
                echo ""
                # 启动子 shell
                bash || true
                echo ""
                echo -e "${GREEN}返回菜单${NC}"
                show_control
                echo ""
                ;;
            0)
                echo "退出后可用: cd /tmp/deb_work 进入工作目录"
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

    # 重打包（先 tar 再压缩）
    pack_tar() {
        local dir="$1" out="$2"
        local tmp_tar="${out%.*}.tar"  # control.tar / data.tar
        # 先创建 tar
        tar cf "$tmp_tar" -C "$dir" . 2>/dev/null || return 1
        # 再压缩
        case "${out##*.}" in
            xz)   xz -f "$tmp_tar" 2>/dev/null || gzip -f "$tmp_tar" && mv "${tmp_tar}.gz" "$out" ;;
            gz)   gzip -f "$tmp_tar" ;;
            zst)  zstd -f "$tmp_tar" 2>/dev/null || gzip -f "$tmp_tar" && mv "${tmp_tar}.gz" "$out" ;;
            *)    gzip -f "$tmp_tar" && mv "${tmp_tar}.gz" "$out" ;;
        esac
        # 确认输出存在
        [ -f "$out" ] && return 0
        # 最后手段：直接 gzip
        gzip -f "$tmp_tar" 2>/dev/null
        mv "${tmp_tar}.gz" "$out" 2>/dev/null && return 0
        return 1
    }

    pack_tar "control" "control.tar.$ctrl_ext" || pack_tar "control" "control.tar.gz"
    pack_tar "data" "data.tar.$data_ext" || pack_tar "data" "data.tar.gz"

    # 更新扩展名变量
    ctrl_ext="gz"; data_ext="gz"
    for f in control.tar.*; do [ -f "$f" ] && ctrl_ext="${f##*.}" && break; done
    for f in data.tar.*; do [ -f "$f" ] && data_ext="${f##*.}" && break; done

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

    chmod -R 777 "$WORKDIR" 2>/dev/null || true
    rm -rf "$WORKDIR" 2>/dev/null || echo -e "${YELLOW}  清理失败，可手动删: sudo rm -rf $WORKDIR${NC}"
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
                cd "$WORKDIR"
                show_control
                echo ""
                show_data_tree
                echo ""
                echo "操作: vi control/control | find data -type f"
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
