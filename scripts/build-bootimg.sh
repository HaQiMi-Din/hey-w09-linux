#!/usr/bin/env bash
# 用 mkbootimg 打包 boot.img (kernel + dtb + initramfs)
# SM6225 通用偏移参数见底部说明; 若与机型 bootloader 不符, 按 stock boot.img 头调整。
set -euo pipefail
cd "$(dirname "$0")/.."

export OUT="${OUT:-out}"
KERNEL_IMG="$OUT/kernel/Image.gz"
RAMDISK="$OUT/initrd.cpio.gz"
BOOT_IMG="$OUT/boot.img"

# 选择 DTB: 优先 khaje 基础 DTB
DTB=""
for cand in \
    "$OUT/kernel/dtbs/khaje.dtb" \
    "$OUT/kernel/dtbs/qcom/khaje.dtb" \
    "$OUT/kernel/dtbs/khaje-idp.dtb" \
    "$OUT/kernel/dtbs/khaje-qrd.dtb"; do
    [ -f "$cand" ] && DTB="$cand" && break
done
if [ -z "$DTB" ]; then
    DTB=$(find "$OUT/kernel/dtbs" -name '*.dtb' | grep -iE 'khaje' | head -1 || true)
fi
if [ -z "$DTB" ]; then
    DTB=$(find "$OUT/kernel/dtbs" -name '*.dtb' | head -1 || true)
fi
echo ">> base DTB: ${DTB:-<none>}"

# 尝试把 HEY-W09 的 overlay (HEY_W09_VA, board-id 8280) 合并进 DTB,
# 以获得正确的显示面板/触摸/板级配置。失败则回退基础 DTB。
OVERLAY_DTS="kernel/arch/arm64/boot/dts/vendor/qcom/khaje/HEY/HEY_W09_VA/overlay.dts"
MERGED_DTB="$OUT/kernel/dtbs/hey-w09-merged.dtb"
if [ -n "$DTB" ] && [ -f "$OVERLAY_DTS" ] && command -v dtc >/dev/null 2>&1 && command -v fdtoverlay >/dev/null 2>&1; then
    echo ">> merging HEY_W09_VA overlay into $DTB"
    TMPD="$(mktemp -d)"
    if (
        cd kernel
        # 复刻 kbuild cmd_dtc: cpp 预处理 (include-prefixes) -> dtc -@ 编译为 dtbo
        cpp -nostdinc -Iscripts/dtc/include-prefixes -undef -D__DTS__ -x assembler-with-cpp \
            "arch/arm64/boot/dts/vendor/qcom/khaje/HEY/HEY_W09_VA/overlay.dts" -o "$TMPD/overlay.dts.tmp" \
        && dtc -@ -O dtb -o "$TMPD/hey_w09_va.dtbo" -b 0 \
            -i"arch/arm64/boot/dts/vendor/qcom/khaje/HEY/HEY_W09_VA" \
            -i"scripts/dtc/include-prefixes" \
            "$TMPD/overlay.dts.tmp"
    ) && fdtoverlay -i "$DTB" -o "$MERGED_DTB" "$TMPD/hey_w09_va.dtbo"; then
        DTB="$MERGED_DTB"
        echo ">> overlay merged -> $DTB"
    else
        echo ">> WARN: overlay merge failed, fallback to base DTB $DTB"
    fi
    rm -rf "$TMPD"
else
    echo ">> using base DTB (overlay unavailable): ${DTB:-<none>}"
fi

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
