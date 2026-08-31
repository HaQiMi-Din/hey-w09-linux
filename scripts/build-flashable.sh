#!/usr/bin/env bash
# 生成 TWRP / 橙狐(OrangeFox) 可刷入的卡刷包 hey-w09-flashable.zip
# 说明: 荣耀官方 Rec 只接受荣耀私钥签名的包, 无法伪造, 故卡刷包为第三方 Rec 格式;
#       另附 fastboot 直刷产物 (boot.img / rootfs.img / rootfs.tar.xz)。
set -euo pipefail
cd "$(dirname "$0")/.."
export OUT="${OUT:-out}"

DEST="$OUT/flashable"
rm -rf "$DEST"
mkdir -p "$DEST/META-INF/com/google/android"

# 1) 打包镜像
cp -v "$OUT/boot.img" "$DEST/" 2>/dev/null || { echo "ERROR: boot.img 不存在"; exit 1; }
[ -f "$OUT/rootfs.img" ] && cp -v "$OUT/rootfs.img" "$DEST/"
[ -f "$OUT/initrd.cpio.gz" ] && cp -v "$OUT/initrd.cpio.gz" "$DEST/"

# 2) shell update-binary (TWRP/OrangeFox 通用, 无需 edify 二进制)
cat > "$DEST/META-INF/com/google/android/update-binary" <<'SBIN'
#!/sbin/sh
# HEY-W09 Linux (Debian + GNOME) 卡刷包
OUTFD=$1
ZIPFILE=$2
ui_print() { echo "ui_print $1" 1>&"$OUTFD"; echo "ui_print" 1>&"$OUTFD"; }

find_block() {
    for p in "$@"; do
        for b in /dev/block/by-name/$p /dev/block/bootdevice/by-name/$p \
                 /dev/block/platform/*/by-name/$p /dev/block/sd* /dev/block/mmcblk*; do
            [ -b "$b" ] && echo "$b" && return 0
        done
    done
    return 1
}

ui_print "=============================="
ui_print " HEY-W09 Linux (Debian+GNOME)"
ui_print " 官方4.19内核 + busybox initrd"
ui_print "=============================="

mkdir -p /tmp/hey && cd /tmp/hey
if command -v unzip >/dev/null 2>&1; then
    unzip -o "$ZIPFILE" boot.img rootfs.img >/dev/null 2>&1
else
    # 无 unzip 时直接从 zip 用 dd 抽取
    mkdir -p /tmp/hey/x
    ( cd /tmp/hey/x && busybox unzip -o "$ZIPFILE" boot.img rootfs.img 2>/dev/null )
    mv /tmp/hey/x/boot.img /tmp/hey/ 2>/dev/null || true
    mv /tmp/hey/x/rootfs.img /tmp/hey/ 2>/dev/null || true
fi

BOOT=$(find_block boot)
if [ -n "$BOOT" ] && [ -f /tmp/hey/boot.img ]; then
    ui_print "刷入 boot.img -> $BOOT"
    dd if=/tmp/hey/boot.img of="$BOOT" bs=4096 2>/dev/null || dd if=/tmp/hey/boot.img of="$BOOT"
    sync
else
    ui_print "ERROR: 未找到 boot 分区或 boot.img!"
fi

ROOTFS=$(find_block rootfs debian data userdata)
if [ -n "$ROOTFS" ] && [ -f /tmp/hey/rootfs.img ]; then
    ui_print "刷入 rootfs.img -> $ROOTFS"
    dd if=/tmp/hey/rootfs.img of="$ROOTFS" bs=4096 2>/dev/null || dd if=/tmp/hey/rootfs.img of="$ROOTFS"
    sync
    # 设置 ext4 卷标 debian, 供 initrd 定位根分区
    tune2fs -L debian "$ROOTFS" 2>/dev/null || true
else
    ui_print "WARN: 未找到 rootfs 目标分区, 请用 fastboot flash rootfs rootfs.img"
fi

ui_print "--------------------------------"
ui_print "刷入完成! 重启进入系统。"
ui_print "若无法启动: 回 TWRP 重新刷入, 或改用 fastboot。"
ui_print "--------------------------------"
exit 0
SBIN
chmod +x "$DEST/META-INF/com/google/android/update-binary"

# 3) updater-script 占位 (部分 Rec 会校验存在性)
cat > "$DEST/META-INF/com/google/android/updater-script" <<'EOF'
ui_print("HEY-W09 Linux");
EOF

# 4) 刷机说明
cat > "$DEST/README.txt" <<'EOF'
HEY-W09 (荣耀平板8) Linux 卡刷包
=================================
- 本包需在 TWRP / OrangeFox 等第三方 Recovery 中刷入。
- 荣耀官方 Rec 只接受荣耀私钥签名的包, 本包无法通过其签名校验。
- 刷入内容: boot.img (官方4.19内核+initrd) + rootfs.img (Debian GNOME) -> data/userdata 分区
- 前置条件: 已解锁 bootloader。
- 没有 TWRP 时可用 fastboot:
    fastboot flash boot boot.img
    fastboot flash userdata rootfs.img   # 或对应 rootfs 分区
- 默认登录: root / debian
EOF

# 5) 压缩
( cd "$DEST" && rm -f "../hey-w09-flashable.zip" && zip -r -9 "../hey-w09-flashable.zip" . >/dev/null )
ls -lh "$OUT/hey-w09-flashable.zip"
echo ">> flashable zip 完成"
