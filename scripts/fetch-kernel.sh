#!/usr/bin/env bash
# 拉取 SM6225 (khaje) mainline 内核源码 (linux-sm6225, v6.1 分支)
# mainline 内核才是能引导 Debian 通用发行版用户空间的内核
# 官方 4.19 Android 内核走 scripts/fetch-kernel-official.sh / build-kernel-official.sh
set -euo pipefail
cd "$(dirname "$0")/.."

KERNEL_SRC="${KERNEL_SRC:-kernel}"
MAINLINE_REPO="${MAINLINE_REPO:-https://gitlab.com/TQMatvey/linux-sm6225.git}"
MAINLINE_BRANCH="${MAINLINE_BRANCH:-v6.1-sm6225}"

if [ -d "$KERNEL_SRC/.git" ] || [ -f "$KERNEL_SRC/Makefile" ]; then
    echo ">> kernel source already present at $KERNEL_SRC"
    exit 0
fi

rm -rf "$KERNEL_SRC"
echo ">> cloning mainline SM6225 kernel (${MAINLINE_BRANCH})"
git clone --depth 1 -b "$MAINLINE_BRANCH" "$MAINLINE_REPO" "$KERNEL_SRC"

echo ">> kernel version:"
grep -E "^(VERSION|PATCHLEVEL|SUBLEVEL)" "$KERNEL_SRC/Makefile" | head -3
echo ">> available defconfigs:"
ls "$KERNEL_SRC/arch/arm64/configs/" 2>/dev/null | head
echo ">> SM6225 dtbs:"
ls "$KERNEL_SRC/arch/arm64/boot/dts/qcom/" 2>/dev/null | grep -iE "sm6225|khaje" | head
