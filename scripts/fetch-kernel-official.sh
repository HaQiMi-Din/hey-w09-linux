#!/usr/bin/env bash
# 拉取并解压 HEY-W09 (荣耀平板8) 荣耀官方内核源码 (Linux 4.19.157, Android 12 GKI)
# 来源: HONOR Open Source Release Center, 镜像存放于本仓库 Release 标签 kernel-source
set -euo pipefail
cd "$(dirname "$0")/.."

KERNEL_SRC="${KERNEL_SRC:-kernel}"
RELEASE_URL="${RELEASE_URL:-https://github.com/HaQiMi-Din/hey-w09-linux/releases/download/kernel-source/kernel-source.tar.gz}"

if [ -f "$KERNEL_SRC/Makefile" ]; then
    echo ">> kernel source already present at $KERNEL_SRC"
else
    rm -rf "$KERNEL_SRC" .kernel-tmp
    mkdir -p .kernel-tmp
    echo ">> downloading official HEY-W09 kernel source (4.19.157)"
    wget -q --show-progress -O .kernel-tmp/kernel-source.tar.gz "$RELEASE_URL"
    echo ">> extracting kernel source"
    tar -xzf .kernel-tmp/kernel-source.tar.gz -C .kernel-tmp
    mv .kernel-tmp/kernel "$KERNEL_SRC"
    rm -rf .kernel-tmp
fi

echo ">> kernel version:"
grep -E "^(VERSION|PATCHLEVEL|SUBLEVEL)" "$KERNEL_SRC/Makefile" | head -3
echo ">> device config present:"
ls "$KERNEL_SRC/arch/arm64/configs/vendor/" 2>/dev/null | grep -E "bengal|khaje" || true
