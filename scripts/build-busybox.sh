#!/usr/bin/env bash
# 交叉编译静态 busybox (aarch64) —— 供 initrd 使用
set -euo pipefail
cd "$(dirname "$0")/.."

export OUT="${OUT:-out}"
BB_VER="${BB_VER:-1.36.1}"
BB_DIR="$OUT/busybox"
export ARCH=arm64
export CROSS_COMPILE="${CROSS_COMPILE:-aarch64-linux-gnu-}"

if [ ! -x "$BB_DIR/busybox" ]; then
    rm -rf "$BB_DIR"
    mkdir -p "$BB_DIR"
    echo ">> downloading busybox ${BB_VER}"
    SRC_ARCHIVE=""
    if curl -fsSL --max-time 300 -o "$OUT/busybox-src.tar.bz2" \
        "https://busybox.net/downloads/busybox-${BB_VER}.tar.bz2"; then
        SRC_ARCHIVE="$OUT/busybox-src.tar.bz2"
    else
        echo ">> busybox.net 慢, 改用 GitHub mirror"
        curl -fsSL --max-time 300 -o "$OUT/busybox-src.tar.gz" \
            "https://github.com/mirror/busybox/archive/refs/tags/${BB_VER}.tar.gz"
        SRC_ARCHIVE="$OUT/busybox-src.tar.gz"
    fi
    case "$SRC_ARCHIVE" in
        *.tar.gz) tar -xzf "$SRC_ARCHIVE" -C "$OUT" ;;
        *)        tar -xjf "$SRC_ARCHIVE" -C "$OUT" ;;
    esac
    rm -rf "$BB_DIR" && mv "$OUT"/busybox-${BB_VER} "$BB_DIR"
    rm -f "$OUT/busybox-src.tar.bz2" "$OUT/busybox-src.tar.gz"
fi

cd "$BB_DIR"
echo ">> configuring busybox (defconfig + STATIC)"
make defconfig
# 静态链接
sed -i 's/^# CONFIG_STATIC is not set$/CONFIG_STATIC=y/' .config
sed -i 's/^CONFIG_STATIC=.*/CONFIG_STATIC=y/' .config
# 确保关键 applet 开启 (defconfig 默认已全开, 这里兜底)
for sym in CONFIG_SH CONFIG_ASH CONFIG_MOUNT CONFIG_UMOUNT CONFIG_SWITCH_ROOT \
           CONFIG_BLKID CONFIG_MODPROBE CONFIG_INSMOD CONFIG_MDEV CONFIG_WGET \
           CONFIG_CHPASSWD CONFIG_ADDUSER CONFIG_TAR CONFIG_CAT CONFIG_LS; do
    sed -i "s/^# $sym is not set\$/$sym=y/" .config
done
grep -q "^CONFIG_STATIC=y" .config && echo "STATIC=yes" || { echo "CONFIG_STATIC=y" >> .config; }

echo ">> building busybox with $(nproc) cores"
make -j"$(nproc)" busybox

[ -x busybox ] && file busybox
echo ">> busybox build done -> $BB_DIR/busybox"
