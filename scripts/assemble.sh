#!/usr/bin/env bash
# 汇总产物: 压缩 rootfs, 生成 ext4 镜像, 整理 out/
set -euo pipefail
cd "$(dirname "$0")/.."

export OUT="${OUT:-out}"
ROOTFS="$OUT/rootfs"

echo ">> compressing rootfs -> rootfs.tar.xz (xz -9, 可能较慢)"
tar -C "$ROOTFS" -cJf "$OUT/rootfs.tar.xz" .
ls -lh "$OUT/rootfs.tar.xz"

# 生成可直接 fastboot flash 的 ext4 镜像(可选; 失败不阻断)
if command -v mkfs.ext4 >/dev/null 2>&1 && command -v mount >/dev/null 2>&1; then
    echo ">> creating ext4 rootfs image (rootfs.img)"
    ROOTFS_SIZE_MB=$(du -sm "$ROOTFS" | awk '{print int($1*1.25)+512}')
    echo "   target size: ${ROOTFS_SIZE_MB} MB"
    truncate -s "${ROOTFS_SIZE_MB}M" "$OUT/rootfs.img"
    mkfs.ext4 -F -L debian "$OUT/rootfs.img" >/dev/null
    mkdir -p /tmp/rootfs-mnt
    sudo mount -o loop "$OUT/rootfs.img" /tmp/rootfs-mnt
    sudo cp -a "$ROOTFS"/. /tmp/rootfs-mnt/
    sudo umount /tmp/rootfs-mnt
    ls -lh "$OUT/rootfs.img"
else
    echo ">> skipped rootfs.img (mkfs.ext4/mount unavailable)"
fi

echo ">> final output:"
find "$OUT" -maxdepth 1 -type f -exec ls -lh {} \;
