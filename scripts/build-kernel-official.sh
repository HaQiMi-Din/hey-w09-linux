#!/usr/bin/env bash
# 交叉编译 HEY-W09 (khaje) 荣耀官方 4.19 ARM64 内核 (Android 12 GKI)
# 设备配置: arch/arm64/configs/vendor/bengal_defconfig (CONFIG_ARCH_KHAJE=y)
#
# 工具链: clang (厂商官方 build.config.common 即 LLVM=1) + aarch64-linux-gnu binutils。
# 之前用 GCC 独立编译持续失败, 换成官方同款 clang 是正确路线。
set -euo pipefail
cd "$(dirname "$0")/.."

export ARCH=arm64
export KERNEL_SRC="${KERNEL_SRC:-kernel}"
export OUT="${OUT:-out}"

# clang 版本选择: Ubuntu 22.04 上 clang-14 (对应 Android clang-r399163b ~ clang 13)
CC_BIN="$(command -v clang-14 || command -v clang || true)"
if [ -z "$CC_BIN" ]; then
    echo "ERROR: clang not found. Install clang-14 (workflow should install it)."
    exit 1
fi
echo ">> compiler: $CC_BIN ($("$CC_BIN" --version | head -1))"

cd "$KERNEL_SRC"

# ---- 源码补丁 (根因已定位, 见 patch-vendor-419.sh) ----
bash ../scripts/patch-vendor-419.sh

# ---- 配置 ----
CONFIG_TARGET="vendor/bengal_defconfig"
[ -f arch/arm64/configs/vendor/khaje_defconfig ] && CONFIG_TARGET="vendor/khaje_defconfig"
echo ">> kernel config: $CONFIG_TARGET"
make CC="$CC_BIN" "$CONFIG_TARGET"

echo ">> applying Debian-boot config fixes"
./scripts/config \
  --enable DEVTMPFS --enable DEVTMPFS_MOUNT --enable TMPFS \
  --enable BLK_DEV_INITRD --enable RD_GZIP \
  --enable EXT4_FS --enable F2FS_FS --enable OVERLAY_FS \
  --enable MODULES --enable MODULE_UNLOAD \
  --enable SERIAL_MSM --enable SERIAL_MSM_CONSOLE \
  --enable INPUT_TOUCHSCREEN --enable BLK_DEV_LOOP --enable BINFMT_MISC
# BOOST_KILL 是 Kconfig default y 的厂商项, 但其信号代码引用缺失的 extern 声明,
# 且该"杀进程时提升到快速核"功能对本发行版无意义 -> 强制关闭
./scripts/config --disable BOOST_KILL
# 关闭 -Werror 类告警当错 (厂商在 clang 下无此问题, 独立构建保险起见)
./scripts/config --disable WERROR 2>/dev/null || true
make CC="$CC_BIN" olddefconfig

echo ">> building kernel (Image.gz + dtbs + modules) with $(nproc) cores [clang]"
make -j"$(nproc)" \
     CC="$CC_BIN" CLANG_TRIPLE=aarch64-linux-gnu- CROSS_COMPILE=aarch64-linux-gnu- \
     KCFLAGS="-Wno-error" \
     Image.gz dtbs modules

# ---- 产物收集 ----
OUT_ABS="$(cd .. && pwd)/$OUT"
mkdir -p "$OUT_ABS/kernel"
cp -v arch/arm64/boot/Image.gz "$OUT_ABS/kernel/"
mkdir -p "$OUT_ABS/kernel/dtbs"
find arch/arm64/boot/dts -name '*.dtb' -exec cp -v {} "$OUT_ABS/kernel/dtbs/" \;
cp -v .config "$OUT_ABS/kernel/hey-w09.config"
echo ">> installing kernel modules into staging (out/modules-stage)"
mkdir -p "$OUT_ABS/modules-stage"
make modules_install INSTALL_MOD_PATH="$OUT_ABS/modules-stage" \
     CC="$CC_BIN" CLANG_TRIPLE=aarch64-linux-gnu- CROSS_COMPILE=aarch64-linux-gnu-
echo ">> kernel build done"
ls -lh "$OUT_ABS/kernel/Image.gz"
ls "$OUT_ABS/kernel/dtbs/" | head
