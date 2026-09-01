#!/usr/bin/env bash
# 用 debootstrap 构建 Debian (bookworm) ARM64 根文件系统
# 预装: GNOME 桌面 (gdm3) + Firefox (firefox-esr) + NetworkManager + WiFi 固件
# 包管理器: apt / dpkg (Debian 自带)
# 在 GitHub Actions(有 root + qemu-user)中运行
set -euo pipefail
cd "$(dirname "$0")/.."
export OUT="${OUT:-out}"
ROOTFS="$OUT/rootfs"
SUITE="${SUITE:-bookworm}"
MIRROR="${MIRROR:-http://deb.debian.org/debian/}"
# 含 non-free-firmware: WiFi 固件 (ath10k/ath11k/ath9k/realtek) 所在组件
COMPONENTS="main,non-free-firmware"
INCLUDE="systemd,systemd-sysv,dbus,locales,apt,sudo,udev,kmod,initramfs-tools,net-tools,wpasupplicant,openssh-server,iproute2,procps,iptables"

echo ">> debootstrap Debian $SUITE (arm64) -> $ROOTFS"
rm -rf "$ROOTFS"
mkdir -p "$ROOTFS"
sudo debootstrap --arch=arm64 --foreign --variant=minbase \
  --components="$COMPONENTS" \
  --include="$INCLUDE" \
  "$SUITE" "$ROOTFS" "$MIRROR"
# qemu 用户态模拟, 让 arm64 二进制可在 x86_64 runner 上运行
sudo cp -v "$(command -v qemu-aarch64-static)" "$ROOTFS/usr/bin/"
echo ">> debootstrap second-stage (configure packages under qemu)"
sudo chroot "$ROOTFS" /debootstrap/debootstrap --second-stage

# 源: 开启 contrib + non-free + non-free-firmware (WiFi 固件)
# 注意: Debian 的 security 仓库是独立域名 debian-security, 不能直接拼在 $MIRROR 后面
SEC_MIRROR="${SEC_MIRROR:-http://deb.debian.org/debian-security}"
sudo tee "$ROOTFS/etc/apt/sources.list" >/dev/null <<EOF
deb $MIRROR $SUITE main contrib non-free non-free-firmware
deb ${MIRROR} $SUITE-updates main contrib non-free non-free-firmware
deb $SEC_MIRROR $SUITE-security main contrib non-free non-free-firmware
EOF

echo ">> install GNOME + Firefox + WiFi 固件"
sudo chroot "$ROOTFS" apt-get update
sudo chroot "$ROOTFS" bash -c 'export DEBIAN_FRONTEND=noninteractive
apt-get install -y \
  gnome-core gdm3 gnome-tweaks gnome-terminal nautilus \
  firefox-esr \
  network-manager network-manager-gnome \
  xserver-xorg xserver-xorg-video-fbdev xserver-xorg-input-libinput \
  pipewire pipewire-pulse wireplumber gstreamer1.0-pipewire \
  fonts-noto-cjk fonts-wqy-zenhei fonts-wqy-microhei \
  firmware-linux firmware-atheros firmware-realtek firmware-iwlwifi \
  dbus-x11'
# 验证 GNOME / gdm3 / firefox 确实装上, 避免静默降级
sudo chroot "$ROOTFS" bash -c 'test -x /usr/bin/gnome-shell || { echo "ERROR: gnome-shell not installed"; exit 1; }'
sudo chroot "$ROOTFS" bash -c 'test -x /usr/sbin/gdm3 || { echo "ERROR: gdm3 not installed"; exit 1; }'
sudo chroot "$ROOTFS" bash -c 'ls /usr/bin/firefox* >/dev/null 2>&1 || { echo "ERROR: firefox not installed"; exit 1; }'
# gdm3 设为默认显示管理器
sudo chroot "$ROOTFS" bash -c 'systemctl enable gdm3 2>/dev/null || true'
sudo chroot "$ROOTFS" bash -c 'systemctl enable NetworkManager 2>/dev/null || true'

# 基础配置
sudo chroot "$ROOTFS" bash -c 'echo "root:debian" | chpasswd'
sudo chroot "$ROOTFS" bash -c 'echo debian-hey-w09 > /etc/hostname'
sudo tee "$ROOTFS/etc/fstab" >/dev/null <<'EOF'
# 由 initramfs 的 init 挂载, 此处供 systemd 参考
PARTLABEL=debian / ext4 defaults 0 1
EOF
# 标记 rootfs 身份, initramfs 兜底探测用它
echo "debian HEY-W09" | sudo tee "$ROOTFS/etc/debian-version" >/dev/null

# 合并 build-kernel 产出的内核模块(放到 staging, 避免 debootstrap rm -rf 清掉)
if [ -d "$OUT/modules-stage/lib/modules" ]; then
    echo ">> merging kernel modules from modules-stage into rootfs"
    sudo mkdir -p "$ROOTFS/lib/modules"
    sudo cp -a "$OUT/modules-stage/lib/modules/." "$ROOTFS/lib/modules/"
    sudo chroot "$ROOTFS" bash -c 'cd /lib/modules && for d in *; do [ -d "$d" ] && depmod -b / "$d" 2>/dev/null || true; done'
fi
echo ">> rootfs build done"
sudo du -sh "$ROOTFS" 2>/dev/null || du -sh "$ROOTFS" 2>/dev/null || true
