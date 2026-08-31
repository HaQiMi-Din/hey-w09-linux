# 刷入指南 (HEY-W09 → Debian + KDE)

> 前提: 已获取 bootloader 解锁或等效的绕过手段。未解锁时以下操作不可执行。
> 风险自负, 先备份。

## 1. 准备分区

用第三方 recovery (如 TWRP/OrangeFox, 需对应 HEY-W09) 或 `adb shell` + `parted` 操作 UFS:

```bash
# 进入 recovery
adb reboot recovery

# 查看分区, 找到 userdata 所在盘
adb shell
ls -l /dev/block/bootdevice/by-name/ | grep -E "userdata|boot|dtbo|vbmeta"

# 缩减 userdata, 分出 debian 分区 (示例: sda 上 userdata 之后)
parted /dev/block/sda
(parted) print
(parted) resizepart <userdata号>
(parted) mkpart debian ext4 <起始> <结束>
(parted) quit
```

## 2. 写入根文件系统

```bash
# 方式 A: ext4 镜像直接 flash
adb shell "parted /dev/block/sda mkpart debian ext4 ..."   # 见上
fastboot flash debian rootfs.img

# 方式 B: 从 rootfs.tar.xz 解压到 ext4 分区
adb shell "mkdir -p /mnt/debian && mount /dev/block/by-name/debian /mnt/debian"
adb push rootfs.tar.xz /sdcard/
adb shell "tar -xJf /sdcard/rootfs.tar.xz -C /mnt/debian"
```

## 3. 禁用 AVB 验证

```bash
fastboot flash vbmeta_ab --disable-verification --disable-verity vbmeta.img
fastboot erase dtbo_ab   # 可选: 清除设备树
```

## 4. 刷入 boot.img

```bash
fastboot flash boot boot.img   # 或 boot_ab
fastboot reboot
```

## 5. 首次进入系统

- 默认账号 `root` / `debian`
- 桌面: KDE Plasma (sddm 登录)
- 屏幕方向: 系统设置 → 显示和监视器 → 旋转 270°
- 键盘/语言: 系统设置 → 区域设置 → 语言 → 添加简体中文
- 网络: 系统设置 → 连接 (NetworkManager / plasma-nm) 配置 WiFi
- 音频: 已安装 pipewire/pipewire-pulse; 若音量异常
  ```bash
  systemctl --user disable pulseaudio.socket pulseaudio.service 2>/dev/null
  systemctl --user mask pulseaudio 2>/dev/null
  systemctl --user enable pipewire.socket pipewire.service pipewire-pulse.socket pipewire-pulse.service
  ```

## 6. 调整 boot.img 参数 (bootloader 不识别时)

```bash
# 查看原厂 boot.img 头
# 需要先从固件包提取 boot.img (magiskboot / unpack_bootimg)
magiskboot unpack stock-boot.img
cat header
```
将 `header_version / base / kernel_offset / ramdisk_offset / tags_offset / pagesize` 填回
`scripts/build-bootimg.sh` 的环境变量后重新构建, 例如:

```bash
BASE=0x00000000 KERNEL_OFFSET=0x00008000 RAMDISK_OFFSET=0x01000000 \
TAGS_OFFSET=0x00000100 PAGESIZE=2048 HEADER_VERSION=2 \
bash scripts/build-bootimg.sh
```

## 回退

刷回原厂 boot 分区与恢复 userdata 分区大小, 或整机恢复官方固件即可。
