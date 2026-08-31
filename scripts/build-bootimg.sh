#!/usr/bin/env bash
# 用 mkbootimg 打包 boot.img (kernel + dtb + initramfs)
# SM6225 通用偏移参数见底部说明; 若与机型 bootloader 不符, 按 stock boot.img 头调整。
set -euo pipefail
cd "$(dirname "$0")/.."

export OUT="${OUT:-out}"
KERNEL_IMG="$OUT/kernel/Image.gz"
RAMDISK="$OUT/initrd.cpio.gz"
BOOT_IMG="$OUT/boot.img"

# 选择 DTB (mainline: sm6225-lenovo-tb128fu.dtb; 官方 4.19: khaje dtb), 没有就用目录下第一个
DTB=""
for cand in \
    "$OUT/kernel/dtbs/qcom/sm6225-lenovo-tb128fu.dtb" \
    "$OUT/kernel/dtbs/sm6225-lenovo-tb128fu.dtb" \
    "$OUT/kernel/dtbs/qcom/khaje-hey.dtb" \
    "$OUT/kernel/dtbs/qcom/khaje-Hey_W09_VA.dtb" \
    "$OUT/kernel/dtbs/qcom/khaje-Hey-W09.dtb" \
    "$OUT/kernel/dtbs/qcom/khaje-qrd.dtb" \
    "$OUT/kernel/dtbs/qcom/khaje-idp.dtb" \
    "$OUT/kernel/dtbs/qcom/khaje.dtb" \
    "$OUT/kernel/dtbs/khaje-hey.dtb" \
    "$OUT/kernel/dtbs/khaje-qrd.dtb" \
    "$OUT/kernel/dtbs/khaje-idp.dtb" \
    "$OUT/kernel/dtbs/khaje.dtb"; do
    [ -f "$cand" ] && DTB="$cand" && break
done
if [ -z "$DTB" ]; then
    DTB=$(find "$OUT/kernel/dtbs" -name '*.dtb' | grep -iE 'khaje|hey' | head -1 || true)
fi
if [ -z "$DTB" ]; then
    DTB=$(find "$OUT/kernel/dtbs" -name '*.dtb' | head -1 || true)
fi
echo ">> using DTB: ${DTB:-<none>}"

# SM6225 (khaje) 典型 boot header v2 偏移
BASE="${BASE:-0x00000000}"
KERNEL_OFFSET="${KERNEL_OFFSET:-0x00008000}"
RAMDISK_OFFSET="${RAMDISK_OFFSET:-0x01000000}"
TAGS_OFFSET="${TAGS_OFFSET:-0x00000100}"
PAGESIZE="${PAGESIZE:-4096}"
HEADER_VERSION="${HEADER_VERSION:-2}"

CMD_LINE="${CMD_LINE:-console=ttyMSM0,115200n8 rootwait androidboot.hardware=qcom androidboot.console=ttyMSM0}"

ARGS=(--kernel "$KERNEL_IMG" --ramdisk "$RAMDISK")
[ -n "$DTB" ] && ARGS+=(--dtb "$DTB")
ARGS+=(
  --cmdline "$CMD_LINE"
  --base "$BASE"
  --kernel_offset "$KERNEL_OFFSET"
  --ramdisk_offset "$RAMDISK_OFFSET"
  --tags_offset "$TAGS_OFFSET"
  --pagesize "$PAGESIZE"
  --header_version "$HEADER_VERSION"
  --os_version 12.0.0
  --os_patch_level 2022-07
  -o "$BOOT_IMG"
)

echo ">> mkbootimg ${ARGS[*]}"
mkbootimg "${ARGS[@]}"
ls -lh "$BOOT_IMG"

echo ">> 提示: 若 bootloader 无法识别, 用 magiskboot/unpack_bootimg 查看机型 stock boot.img 的
    header_version/offsets/pagesize 并修正 BASE/KERNEL_OFFSET/RAMDISK_OFFSET/TAGS_OFFSET/PAGESIZE/HEADER_VERSION。"
