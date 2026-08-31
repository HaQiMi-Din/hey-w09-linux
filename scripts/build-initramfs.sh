#!/usr/bin/env bash
# 构建 initrd: 交叉编译的 busybox + 我们的 init + WiFi 模块/固件
set -euo pipefail
cd "$(dirname "$0")/.."

export OUT="${OUT:-out}"
TMP="$OUT/initrd"
rm -rf "$TMP"
mkdir -p "$TMP"/{bin,sbin,dev,proc,sys,newroot,tmp,run,etc,lib,usr/bin,usr/sbin}

# 0) 先交叉编译 busybox
bash scripts/build-busybox.sh

# 1) init + busybox
cp -v initramfs/init "$TMP/init"
chmod +x "$TMP/init"
cp -v "$OUT/busybox/busybox" "$TMP/bin/busybox"
chmod +x "$TMP/bin/busybox"
# busybox applet 链接 (init 里也会 --install, 这里先备好)
"$TMP/bin/busybox" --install -s "$TMP/bin" 2>/dev/null || true
for a in switch_root blkid modprobe mdev mount; do
    ln -sf /bin/busybox "$TMP/bin/$a" 2>/dev/null || true
    ln -sf /bin/busybox "$TMP/sbin/$a" 2>/dev/null || true
done

# 2) WiFi 内核模块 (从已构建的 rootfs/lib/modules 中挑出 wlan 相关, 保留相对路径)
KVER=""
if [ -d "$OUT/rootfs/lib/modules" ]; then
    KVER=$(ls "$OUT/rootfs/lib/modules" | head -1 || true)
fi
if [ -n "$KVER" ] && [ -d "$OUT/rootfs/lib/modules/$KVER" ]; then
    echo ">> copying WiFi kernel modules ($KVER)"
    SRC="$OUT/rootfs/lib/modules/$KVER"
    DST="$TMP/lib/modules/$KVER"
    mkdir -p "$DST"
    # 在模块树内遍历, 拷贝 wifi/网络相关模块并保留相对目录结构
    ( cd "$SRC" && \
      find . -type f \( -iname '*ath10k*' -o -iname '*ath11k*' -o -iname '*wcn36xx*' \
        -o -iname '*wcnss*' -o -iname '*cnss*' -o -iname '*wlan*' -o -iname '*qrtr*' \
        -o -iname '*smem*' -o -iname '*rpmsg*' -o -iname '*glink*' -o -iname '*rmtfs*' \
        -o -iname '*mpm*' \) | while read -r f; do \
            mkdir -p "$DST/$(dirname "$f")"; \
            cp -v "$f" "$DST/$f"; \
        done ) 2>&1 | tail -8
    # 生成 modules.dep / modules.alias (depmod 可跨架构解析 ELF)
    cp -v "$SRC/modules.order" "$DST/" 2>/dev/null || true
    cp -v "$SRC/modules.builtin" "$DST/" 2>/dev/null || true
    if command -v depmod >/dev/null 2>&1; then
        depmod -b "$TMP" "$KVER" 2>/dev/null || true
    fi
    echo "   -> initrd modules size: $(du -sh "$DST" | awk '{print $1}')"
else
    echo ">> WARN: no kernel modules found at out/rootfs/lib/modules (run build-kernel.sh first)"
fi

# 3) WiFi 固件 (从 rootfs/lib/firmware 拷贝; 由 build-rootfs.sh 安装 linux-firmware)
if [ -d "$OUT/rootfs/lib/firmware" ]; then
    echo ">> copying WiFi firmware"
    FWSRC="$OUT/rootfs/lib/firmware"
    FWDST="$TMP/lib/firmware"
    ( cd "$FWSRC" && \
      find . -type f \( -iname '*ath10k*' -o -iname '*ath11k*' -o -iname '*wcn36xx*' \
        -o -iname '*wcnss*' -o -iname '*WCNSS*' -o -iname '*cnss*' -o -iname '*qcom*' \) | while read -r f; do \
            mkdir -p "$FWDST/$(dirname "$f")"; \
            cp -v "$f" "$FWDST/$f"; \
        done ) 2>&1 | tail -5
    echo "   -> initrd firmware size: $(du -sh "$FWDST" | awk '{print $1}')"
fi

# 4) 打包 initrd.cpio.gz
echo ">> packing initrd.cpio.gz"
( cd "$TMP" && find . -print0 | cpio --null -o -H newc 2>/dev/null | gzip -9 > "$OUT/initrd.cpio.gz" )
ls -lh "$OUT/initrd.cpio.gz"
echo ">> initrd size breakdown:"
du -sh "$TMP"/* 2>/dev/null | sort -rh | head
