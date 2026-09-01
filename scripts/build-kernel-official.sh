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
  --disable MODULES \
  --enable SERIAL_MSM --enable SERIAL_MSM_CONSOLE \
  --enable INPUT_TOUCHSCREEN --enable BLK_DEV_LOOP --enable BINFMT_MISC
# BOOST_KILL 是 Kconfig default y 的厂商项, 但其信号代码引用缺失的 extern 声明,
# 且该"杀进程时提升到快速核"功能对本发行版无意义 -> 强制关闭
./scripts/config --disable BOOST_KILL
# SMB1398 副充电器驱动 (仅高端机型), 本机(khaje) 不使用, 但其代码引用不存在的
# POWER_SUPPLY_PROP_INPUT_CURRENT_MAX -> 关闭
./scripts/config --disable SMB1398_CHARGER
# 荣耀 lcdkit 面板框架: 头文件/工具在厂商树 vendor/honor/chipset_common 中,
# 本内核 Release 不包含 -> 独立构建必须关闭 (dsi 代码有 #ifndef 回退路径)
./scripts/config --disable LCD_KIT_DRIVER
# 关闭 -Werror 类告警当错 (厂商在 clang 下无此问题, 独立构建保险起见)
./scripts/config --disable WERROR 2>/dev/null || true
# ---- 链接期修复 ----
# MODVERSIONS 的 __crc_ 符号 + clang/GNU ld 产生危险重定位; 独立系统无外部模块, 关闭
./scripts/config --disable MODVERSIONS 2>/dev/null || true
# GSI 驱动危险重定位 (__crc_gsi_* 无法在共享对象外解析)
./scripts/config --disable GSI 2>/dev/null || true
# 相机遥测 cam_hiview 依赖厂商私有 hiview 模块(源码缺失) -> 关掉整块相机栈
./scripts/config --disable SPECTRA_CAMERA 2>/dev/null || true
# 调试信息在 clang-14 + binutils 2.38 下产生 DWARF 警告并显著增大镜像, 关闭
./scripts/config --disable DEBUG_INFO 2>/dev/null || true
# 关闭 32 位兼容层 (纯 arm64 Debian 不需要): 消除 modpost 中 __NR_compat_* 未定义
./scripts/config --disable COMPAT 2>/dev/null || true
make CC="$CC_BIN" olddefconfig

echo ">> building kernel (Image.gz + dtbs) with $(nproc) cores [clang]"
make -j"$(nproc)" \
     CC="$CC_BIN" CLANG_TRIPLE=aarch64-linux-gnu- CROSS_COMPILE=aarch64-linux-gnu- \
     KCFLAGS="-Wno-error" \
     Image.gz dtbs
# 拆分构建: modpost 编译 .mod.o 前先重生成 generated headers / asm 符号链接,
# 修复 "asm/barrier.h file not found" (vendir 4.19 + clang 的 modpost include 路径问题)
make CC="$CC_BIN" CLANG_TRIPLE=aarch64-linux-gnu- CROSS_COMPILE=aarch64-linux-gnu- \
     KCFLAGS="-Wno-error" prepare
echo ">> building modules [clang]"
make -j"$(nproc)" \
     CC="$CC_BIN" CLANG_TRIPLE=aarch64-linux-gnu- CROSS_COMPILE=aarch64-linux-gnu- \
     KCFLAGS="-Wno-error" \
     modules

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
