#!/usr/bin/env bash
# 用 debootstrap 构建 Kubuntu (Ubuntu noble 24.04) ARM64 根文件系统
# 预装: KDE Plasma 桌面 (sddm) + Firefox (Mozilla 官方 apt 仓库, arm64 deb) + NetworkManager + WiFi 固件
# 包管理器: apt / dpkg (Ubuntu 自带)
# 在 GitHub Actions(有 root + qemu-user)中运行
set -euo pipefail
cd "$(dirname "$0")/.."
export OUT="${OUT:-out}"
ROOTFS="$OUT/rootfs"
SUITE="${SUITE:-noble}"
# Ubuntu arm64 仓库在 ports.ubuntu.com (不是 archive.ubuntu.com)
MIRROR="${MIRROR:-http://ports.ubuntu.com/ubuntu-ports/}"
COMPONENTS="main,universe,multiverse,restricted"
INCLUDE="systemd,systemd-sysv,dbus,locales,apt,sudo,udev,kmod,initramfs-tools,net-tools,wpasupplicant,openssh-server,iproute2,procps,iptables,gnupg"

# debootstrap 需要 Ubuntu noble 的脚本 (runner 自带 debootstrap 用 gutsy 兼容脚本)
sudo ln -sf /usr/share/debootstrap/scripts/gutsy /usr/share/debootstrap/scripts/noble 2>/dev/null || true

echo ">> debootstrap Kubuntu $SUITE (arm64) -> $ROOTFS"
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

# 源: Ubuntu ports (arm64), 含 universe/multiverse (KDE 组件所在)
sudo tee "$ROOTFS/etc/apt/sources.list" >/dev/null <<EOF
deb $MIRROR $SUITE main universe multiverse restricted
deb $MIRROR $SUITE-updates main universe multiverse restricted
deb $MIRROR $SUITE-security main universe multiverse restricted
EOF

echo ">> install KDE Plasma + Firefox + WiFi 固件"
sudo chroot "$ROOTFS" apt-get update -y
sudo chroot "$ROOTFS" bash -c 'export DEBIAN_FRONTEND=noninteractive
apt-get install -y \
  kde-plasma-desktop sddm plasma-nm konsole dolphin kate discover \
  maliit-keyboard onboard \
  network-manager \
  xserver-xorg xserver-xorg-video-fbdev xserver-xorg-input-libinput \
  pipewire pipewire-pulse wireplumber \
  fonts-noto-cjk fonts-wqy-zenhei fonts-wqy-microhei \
  linux-firmware \
  dbus-x11'
# 启用 Maliit 虚拟键盘 (KDE/Plasma 触摸输入)
sudo chroot "$ROOTFS" bash -c 'echo "QT_VIRTUALKEYBOARD=maliit" >> /etc/environment'
# Firefox: Ubuntu 的 firefox 是 snap 过渡包(容器内不可用), 改用 Mozilla 官方 apt 仓库 (支持 arm64 deb)
# 先在主机下载并去armor key, 再拷入 chroot, 避免 chroot 内网络/权限问题
echo ">> adding Mozilla apt repo for Firefox (arm64)"
wget -q https://packages.mozilla.org/apt/repo-signing-key.gpg -O /tmp/mozilla-repo-key.gpg
gpg --batch --dearmor -o "$ROOTFS/usr/share/keyrings/packages.mozilla.org.gpg" /tmp/mozilla-repo-key.gpg
rm -f /tmp/mozilla-repo-key.gpg
sudo tee "$ROOTFS/etc/apt/sources.list.d/mozilla.list" >/dev/null <<'MOZEOF'
deb [signed-by=/usr/share/keyrings/packages.mozilla.org.gpg] https://packages.mozilla.org/apt mozilla main
MOZEOF
sudo chroot "$ROOTFS" bash -c 'export DEBIAN_FRONTEND=noninteractive
apt-get update -y && apt-get install -y firefox'
# 验证 Plasma / sddm / firefox 确实装上, 避免静默降级
sudo chroot "$ROOTFS" bash -c 'test -x /usr/bin/plasma_session || { echo "ERROR: plasma_session not installed"; exit 1; }'
sudo chroot "$ROOTFS" bash -c 'test -x /usr/bin/sddm || { echo "ERROR: sddm not installed"; exit 1; }'
sudo chroot "$ROOTFS" bash -c 'ls /usr/bin/firefox* >/dev/null 2>&1 || { echo "ERROR: firefox not installed"; exit 1; }'
# sddm 设为默认显示管理器
sudo chroot "$ROOTFS" bash -c 'systemctl enable sddm 2>/dev/null || true'
sudo chroot "$ROOTFS" bash -c 'systemctl enable NetworkManager 2>/dev/null || true'

# 基础配置
sudo chroot "$ROOTFS" bash -c 'echo "root:debian" | chpasswd'
sudo chroot "$ROOTFS" bash -c 'echo kubuntu-hey-w09 > /etc/hostname'
sudo tee "$ROOTFS/etc/fstab" >/dev/null <<'EOF'
# 由 initramfs 的 init 挂载, 此处供 systemd 参考
PARTLABEL=kubuntu / ext4 defaults 0 1
EOF
# 标记 rootfs 身份, initramfs 兜底探测用它 (Ubuntu 有 /etc/os-release; 再留一个兼容标记)
echo "kubuntu HEY-W09" | sudo tee "$ROOTFS/etc/kubuntu-version" >/dev/null

# 合并 build-kernel 产出的内核模块(放到 staging, 避免 debootstrap rm -rf 清掉)
if [ -d "$OUT/modules-stage/lib/modules" ]; then
    echo ">> merging kernel modules from modules-stage into rootfs"
    sudo mkdir -p "$ROOTFS/lib/modules"
    sudo cp -a "$OUT/modules-stage/lib/modules/." "$ROOTFS/lib/modules/"
    sudo chroot "$ROOTFS" bash -c 'cd /lib/modules && for d in *; do [ -d "$d" ] && depmod -b / "$d" 2>/dev/null || true; done'
fi
echo ">> rootfs build done"
sudo du -sh "$ROOTFS" 2>/dev/null || du -sh "$ROOTFS" 2>/dev/null || true
