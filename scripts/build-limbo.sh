#!/usr/bin/env bash
# 生成 Limbo (Android QEMU) 可引导的 rootfs 磁盘镜像
# 产物: out/hey-w09-limbo.img (raw ext4, 直接作为 Limbo HDD 使用)
#       out/hey-w09-limbo.zip  (镜像 + Limbo 配置 + 引导说明)
#
# Limbo 不能直接用荣耀厂商内核/DTB (为真实硬件编译)。本包交付:
#   - 与硬件无关的 Debian rootfs (GNOME+Firefox+apt) 的 raw ext4 镜像
#   - 引导时请在 Limbo 内选择 通用 aarch64 内核 (Limbo 自带或主线 6.x)
#   - fstab 已改为 /dev/vda (virtio 磁盘), 兼容 QEMU 通用引导
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="$(pwd)/${OUT:-out}"
export OUT

ROOTFS="$OUT/rootfs"
if [ ! -d "$ROOTFS" ]; then
    echo "ERROR: $ROOTFS not found (run build-rootfs.sh first)"; exit 1
fi

IMG="$OUT/hey-w09-limbo.img"
SZ_MB="${LIMBO_IMG_MB:-8192}"   # 8GB raw ext4 (rootfs 3.9G 需 >8G; 可调)
rm -f "$IMG"
echo ">> creating raw ext4 image ($SZ_MB MB)"
truncate -s "${SZ_MB}M" "$IMG"

# rootfs 的 fstab 改成 /dev/vda (QEMU virtio 磁盘), Limbo 引导用
sudo mkfs.ext4 -q -L hey-w09 "$IMG"
sudo mkdir -p /mnt/limbo-root
sudo mount -o loop "$IMG" /mnt/limbo-root
echo ">> copying rootfs into image (this takes a while)"
sudo cp -a "$ROOTFS"/. /mnt/limbo-root/
# 改写 fstab 为 virtio 盘
echo '/dev/vda / ext4 defaults 0 1' | sudo tee /mnt/limbo-root/etc/fstab >/dev/null
sudo umount /mnt/limbo-root

# 压缩 + Limbo 配置说明
cat > "$OUT/README-LIMBO.txt" <<'EOF'
HEY-W09 rootfs for Limbo (Android QEMU)
========================================
本包是 荣耀平板8 官方4.19 项目产出的 Debian rootfs (GNOME + Firefox + apt/dpkg),
已打包成 raw ext4 磁盘镜像, 可直接在 Limbo 中引导。

【重要】Limbo 是 QEMU 前端, 无法使用荣耀厂商内核/DTB (为真实硬件编译)。
请在 Limbo 中加载 通用 aarch64 (arm64) 内核, 推荐:
  - Limbo 内置的 aarch64 内核, 或
  - 主线 Linux 6.x arm64 Image

【Limbo 配置】
  - Machine   : virt / aarch64
  - CPU       : cortex-a53 (或 a72)
  - RAM       : >=2048 MB (GNOME 需要)
  - Kernel    : 通用 arm64 Image
  - Kernel cmdline: root=/dev/vda rw console=ttyAMA0
  - HDD 0     : hey-w09-limbo.img (raw)
  - Display   : virtio-gpu (或 VGA)
  - Network   : virtio-net (NAT)
  - 登录      : root / debian

【性能】无 KVM 时走 TCG 软件模拟, GNOME 会卡; 若设备 /dev/kvm 可用
(需内核开启 CONFIG_KVM_ARM 且 bootloader 未锁 EL2), 开启 KVM 后流畅很多。
EOF

( cd "$OUT" && rm -f hey-w09-limbo.zip && zip -r -9 hey-w09-limbo.zip hey-w09-limbo.img README-LIMBO.txt >/dev/null )

echo ">> Limbo 产物:"
ls -lh "$IMG" "$OUT/hey-w09-limbo.zip" "$OUT/README-LIMBO.txt"
