#!/bin/bash
#===============================================================
# .deb 解包/重包工具
# 用法:
#   ./deb.sh extract <deb文件>    # 解包到 /tmp/deb_work/
#   ./deb.sh pack   <deb文件>    # 从 /tmp/deb_work/ 重新打包
#===============================================================
set -e

CMD=$1
DEB_FILE=$2
WORKDIR="/tmp/deb_work"

usage() {
    echo "用法:"
    echo "  $0 extract xxx.deb    # 解包"
    echo "  $0 pack   xxx.deb    # 重打包"
    echo ""
    echo "工作目录: $WORKDIR"
    exit 1
}

[ -z "$CMD" ] && usage
[ -z "$DEB_FILE" ] && usage

case "$CMD" in
    extract)
        # 确保 deb 存在
        if [ ! -f "$DEB_FILE" ]; then
            echo "[ERROR] 文件不存在: $DEB_FILE"
            exit 1
        fi

        # 清理旧工作目录
        rm -rf "$WORKDIR"
        mkdir -p "$WORKDIR/control" "$WORKDIR/data"

        # 复制 deb 并解包
        cp "$DEB_FILE" "$WORKDIR/"
        cd "$WORKDIR"
        ar x "$(basename "$DEB_FILE")"

        # 解压 control
        cd control
        tar xf ../control.tar.xz 2>/dev/null || tar xf ../control.tar.gz 2>/dev/null || tar xf ../control.tar.zst 2>/dev/null
        echo "=== control 内容 ==="
        ls -la
        echo ""
        echo "=== control 文件 ==="
        cat control 2>/dev/null || echo "(无 control 文件)"

        # 解压 data
        cd "$WORKDIR/data"
        tar xf ../data.tar.xz 2>/dev/null || tar xf ../data.tar.gz 2>/dev/null || tar xf ../data.tar.zst 2>/dev/null
        echo ""
        echo "=== data 内容 ==="
        find . -type f | head -30
        echo ""
        echo "========================================"
        echo " 解包完成！"
        echo ""
        echo " 编辑文件:"
        echo "   control 文件 -> $WORKDIR/control/"
        echo "   插件文件   -> $WORKDIR/data/"
        echo ""
        echo " 修改完后运行:"
        echo "   $0 pack $DEB_FILE"
        echo "========================================"
        ;;
    pack)
        if [ ! -d "$WORKDIR" ] || [ ! -d "$WORKDIR/control" ]; then
            echo "[ERROR] 工作目录不存在或无效: $WORKDIR"
            echo "请先运行 extract 解包"
            exit 1
        fi

        cd "$WORKDIR"

        # 检测压缩格式（沿用原格式）
        CONTROL_EXT=""
        DATA_EXT=""
        for f in control.tar.*; do
            CONTROL_EXT="${f##*.}"
            break
        done
        for f in data.tar.*; do
            DATA_EXT="${f##*.}"
            break
        done
        [ -z "$CONTROL_EXT" ] && CONTROL_EXT="xz"
        [ -z "$DATA_EXT" ] && DATA_EXT="xz"

        echo "压缩格式: control.tar.$CONTROL_EXT, data.tar.$DATA_EXT"

        # 重新打包 control
        cd control
        tar caf "../control.tar.$CONTROL_EXT" *
        cd "$WORKDIR"

        # 重新打包 data
        cd data
        tar caf "../data.tar.$DATA_EXT" *
        cd "$WORKDIR"

        # 重新打包 deb
        NEW_DEB="$(basename "$DEB_FILE")"
        ar rcs "$NEW_DEB" debian-binary "control.tar.$CONTROL_EXT" "data.tar.$DATA_EXT"

        # 替换原文件
        cp "$NEW_DEB" "$DEB_FILE"

        echo ""
        echo "========================================"
        echo " 打包完成！"
        echo " 已更新: $DEB_FILE"
        echo "========================================"

        # 清理
        rm -rf "$WORKDIR"
        ;;
    *)
        usage
        ;;
esac
