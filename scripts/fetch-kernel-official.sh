#!/usr/bin/env bash
# 拉取并解压 HEY-W09 (荣耀平板8) 荣耀官方内核源码 (Linux 4.19.157, Android 12 GKI)
# 来源: HONOR Open Source Release Center, 镜像存放于本仓库 Release 标签 kernel-source
set -euo pipefail
cd "$(dirname "$0")/.."

KERNEL_SRC="${KERNEL_SRC:-kernel}"
# 从 Release 动态获取官方源码包地址 (asset 可能被改名, 硬编码 URL 易 404)
if [ -z "${RELEASE_URL:-}" ]; then
    RELEASE_URL="$(curl -fsSL "https://api.github.com/repos/HaQiMi-Din/hey-w09-linux/releases/tags/kernel-source" \
        | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['assets'][0]['browser_download_url'])")"
fi
echo ">> release url: $RELEASE_URL"

if [ -f "$KERNEL_SRC/Makefile" ]; then
    echo ">> kernel source already present at $KERNEL_SRC"
    exit 0
fi

rm -rf "$KERNEL_SRC" .kernel-tmp
mkdir -p .kernel-tmp

echo ">> downloading official HEY-W09 kernel source (4.19.157)"
wget -q --show-progress -O .kernel-tmp/source.rar "$RELEASE_URL"

# 解压 rar (rar5): 优先系统 7z, 否则下载 7-Zip 静态 7zz
SZ=""
if command -v 7z >/dev/null 2>&1; then
    SZ=7z
elif command -v 7zz >/dev/null 2>&1; then
    SZ=7zz
else
    echo ">> fetching 7-Zip static 7zz"
    wget -q -O .kernel-tmp/7z.tar.xz "https://www.7-zip.org/a/7z2602-linux-x64.tar.xz"
    tar -xf .kernel-tmp/7z.tar.xz -C .kernel-tmp 7zz
    chmod +x .kernel-tmp/7zz
    SZ=".kernel-tmp/7zz"
fi
echo ">> extracting rar with $SZ"
if [ "$SZ" = "7z" ] || [ "$SZ" = "7zz" ]; then
    ( cd .kernel-tmp && "$SZ" x -y source.rar >/dev/null 2>&1 || "$SZ" x -y source.rar )
else
    ( cd .kernel-tmp && "$OLDPWD/$SZ" x -y source.rar >/dev/null 2>&1 || "$OLDPWD/$SZ" x -y source.rar )
fi

echo ">> extracting Code_Opensource.tar.gz"
tar -xzf .kernel-tmp/Hendry-W09D_MagicUI6.1_Opensource/Code_Opensource.tar.gz -C .kernel-tmp
mv .kernel-tmp/Code_Opensource/kernel "$KERNEL_SRC"
rm -rf .kernel-tmp

echo ">> kernel version:"
grep -E "^(VERSION|PATCHLEVEL|SUBLEVEL)" "$KERNEL_SRC/Makefile" | head -3
echo ">> device config present:"
ls "$KERNEL_SRC/arch/arm64/configs/vendor/" 2>/dev/null | grep -E "bengal|khaje" || true
