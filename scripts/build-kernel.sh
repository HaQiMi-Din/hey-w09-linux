#!/usr/bin/env bash
# 交叉编译 SM6225 (khaje) mainline 6.1 ARM64 内核 -> Image.gz + dtbs + modules
# 默认 defconfig: sm6125_defconfig (SM6225 fork 自带), DTB: sm6225-lenovo-tb128fu.dtb
set -euo pipefail
cd "$(dirname "$0")/.."

export ARCH=arm64
export CROSS_COMPILE="${CROSS_COMPILE:-aarch64-linux-gnu-}"
export KERNEL_SRC="${KERNEL_SRC:-kernel}"
export OUT="${OUT:-out}"

OUT_ABS="$(cd "$KERNEL_SRC" 2>/dev/null && cd .. && pwd)/$OUT"
# 缓存命中则跳过编译 (out/kernel + out/modules-stage 由 actions/cache 恢复)
if [ -f "$OUT_ABS/kernel/Image.gz" ] && [ -d "$OUT_ABS/modules-stage/lib/modules" ]; then
    echo ">> kernel already built (cache hit), skipping rebuild"
    exit 0
fi

cd "$KERNEL_SRC"

# 选配置: SM6225 fork 自带 sm6125_defconfig; 否则用默认 defconfig
if [ -f arch/arm64/configs/sm6125_defconfig ]; then
    CONFIG_TARGET="sm6125_defconfig"
elif [ -f arch/arm64/configs/sm6225_defconfig ]; then
    CONFIG_TARGET="sm6225_defconfig"
else
    CONFIG_TARGET="defconfig"
fi
echo ">> using kernel config: $CONFIG_TARGET"
make "$CONFIG_TARGET"

echo ">> enabling Debian-boot essentials"
./scripts/config \
  --enable DEVTMPFS --enable DEVTMPFS_MOUNT --enable TMPFS \
  --enable BLK_DEV_INITRD --enable RD_GZIP \
  --enable EXT4_FS --enable F2FS_FS --enable OVERLAY_FS \
  --enable MODULES --enable MODULE_UNLOAD \
  --enable SERIAL_MSM_GENI --enable SERIAL_MSM_GENI_CONSOLE \
  --enable INPUT_TOUCHSCREEN --enable BLK_DEV_LOOP --enable BINFMT_MISC \
  --enable WCN36XX --enable ATH10K_SNOC --enable ATH11K_AHB --enable QCOM_WCNSS_PIL
make olddefconfig

echo ">> building kernel (Image.gz + dtbs + modules) with $(nproc) cores"
make -j"$(nproc)" Image.gz dtbs modules

# 产物收集
mkdir -p "$OUT_ABS/kernel"
cp -v arch/arm64/boot/Image.gz "$OUT_ABS/kernel/"
mkdir -p "$OUT_ABS/kernel/dtbs"
find arch/arm64/boot/dts -name '*.dtb' -exec cp -v {} "$OUT_ABS/kernel/dtbs/" \;
cp -v .config "$OUT_ABS/kernel/hey-w09-mainline.config"
echo ">> installing kernel modules into staging dir (out/modules-stage)"
mkdir -p "$OUT_ABS/modules-stage"
make modules_install INSTALL_MOD_PATH="$OUT_ABS/modules-stage"
echo ">> kernel build done"
ls -lh "$OUT_ABS/kernel/Image.gz"
