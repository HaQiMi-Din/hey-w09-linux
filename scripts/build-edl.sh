#!/usr/bin/env bash
# 生成高通 9008 (EDL) 模式线刷包目录 hey-w09-edl/
# 适用: QFIL / qdl 通过 9008 模式刷入 boot.img 与 rootfs.img。
#
# 安全须知(务必阅读):
#   rawprogram0.xml 中的 start_sector / physical_partition_number 是设备 eMMC 物理布局,
#   不同批次/固件可能不同。刷错扇区有变砖风险(9008 一般可救)。
#   刷入前务必先从设备真实 GPT 校准偏移:
#     - 已解锁+root/TWRP:  `sgdisk --print /dev/block/mmcblk0` 或 `cat /proc/partitions`
#     - 或用 9008 前在 Android 里 `ls -l /dev/block/by-name/`
#   将 boot / userdata 的"起始扇区"填入下方 rawprogram0.xml 的 start_sector。
set -euo pipefail
cd "$(dirname "$0")/.."
export OUT="${OUT:-out}"

DEST="$OUT/hey-w09-edl"
rm -rf "$DEST"
mkdir -p "$DEST/images"

# 1) 镜像
cp -v "$OUT/boot.img" "$DEST/images/" 2>/dev/null || { echo "ERROR: boot.img 缺失"; exit 1; }
[ -f "$OUT/rootfs.img" ] && cp -v "$OUT/rootfs.img" "$DEST/images/" || true

# 2) rawprogram0.xml (偏移为占位, 必须按设备 GPT 校准)
BOOT_SECTOR="${BOOT_SECTOR:-40960}"      # boot 起始扇区(占位, 需校准)
BOOT_SIZE_KB="${BOOT_SIZE_KB:-65536}"    # boot 大小 KB (64MB 占位)
USERDATA_SECTOR="${USERDATA_SECTOR:-2000000}"  # userdata 起始扇区(占位, 需校准)
USERDATA_SIZE_KB="${USERDATA_SIZE_KB:-16777216}" # userdata 大小 KB (16GB 占位)
LUN="${LUN:-0}"
cat > "$DEST/rawprogram0.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<data>
  <!-- HEY-W09 (荣耀平板8 / khaje) Linux 线刷包 -->
  <!-- !!! 以下 start_sector / LUN 为占位, 必须按设备真实 GPT 校准后再刷 !!! -->
  <program SECTOR_SIZE_IN_BYTES="512" file_sector_offset="0" filename="boot.img"
           label="boot" num_partition_sectors="${BOOT_SECTOR}"
           physical_partition_number="${LUN}" size_in_KB="${BOOT_SIZE_KB}"
           sparse="false" start_byte_as_string="hex:0x$((BOOT_SECTOR*512))"/>
  <program SECTOR_SIZE_IN_BYTES="512" file_sector_offset="0" filename="rootfs.img"
           label="userdata" num_partition_sectors="${USERDATA_SECTOR}"
           physical_partition_number="${LUN}" size_in_KB="${USERDATA_SIZE_KB}"
           sparse="false" start_byte_as_string="hex:0x$((USERDATA_SECTOR*512))"/>
</data>
EOF

# 3) patch0.xml (最小基础)
cat > "$DEST/patch0.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<patches>
  <!-- 无额外补丁; 若设备需要 GPT 头修复或 DDR 配置, 由 firehose 侧处理 -->
</patches>
EOF

# 4) 刷机说明
cat > "$DEST/README-9008.txt" <<'EOF'
HEY-W09 (荣耀平板8 / khaje) 9008 线刷包
======================================
本包用于在高通 9008 (EDL / Emergency Download) 模式下, 通过 QFIL 或 qdl 刷入
boot.img (官方4.19内核+initrd) 与 rootfs.img (Debian GNOME 根文件系统)。

【重要 - 刷前必读】
1. 9008 模式进入: 关机后按住 音量上+下 同时插 USB; 或已 root 时 `adb reboot edl`。
   设备管理器应出现 "Qualcomm HS-USB QDLoader 9008"。
2. 需要设备的 firehose 程序员文件 prog_firehose_ddr.elf (khaje/SM6225 专用),
   请从设备原厂固件 / 备份中获取, 放入本目录。
3. 本包 rawprogram0.xml 中的 start_sector / LUN 为占位值!
   必须先从设备读取真实 GPT 校准:
   - 在 TWRP / 已解锁 Android 中执行: `sgdisk --print /dev/block/mmcblk0`
   - 或 `cat /proc/partitions` / `ls -l /dev/block/by-name/`
   - 将 boot 与 userdata 分区的实际起始扇区填入 rawprogram0.xml。
   刷错扇区有变砖风险!

【QFIL 刷入步骤】
1. 打开 Qualcomm Flash Image Loader (QFIL)
2. Select Programmer -> 选择 prog_firehose_ddr.elf
3. 选择 "Flat Build" -> 添加本目录 rawprogram0.xml 与 patch0.xml
4. 点击 Download / Flash
5. 完成后设备重启进入 Linux (默认登录 root / debian)

【替代方案】
- 官方 Rec 只接受荣耀签名包, 无法直刷。
- 推荐: 解锁 bootloader 后 TWRP 卡刷 (hey-w09-flashable.zip) 或 fastboot 直刷。
EOF

# 5) 压缩为顶层 zip (便于随产物/Release 下载)
( cd "$OUT" && rm -f "hey-w09-edl.zip" && zip -r -9 "hey-w09-edl.zip" hey-w09-edl >/dev/null )
ls -lh "$OUT/hey-w09-edl.zip"

ls -lh "$DEST/" "$DEST/images/"
echo ">> 9008 线刷包目录完成: $DEST (rawprogram0.xml 偏移需按设备 GPT 校准)"
