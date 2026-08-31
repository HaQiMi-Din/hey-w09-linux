# hey-w09-linux

把 **荣耀平板8 (Honor Pad 8, HEY-W09, Snapdragon 680 / SM6225 / khaje, arm64)** 变成一台完整 Linux 平板。

方案参考「小米平板运行 deepin」：使用 **荣耀官方 4.19 内核**(自带全部厂商驱动：触摸、WiFi、Adreno GPU、显示), 配 Debian rootfs + 自定义 initrd 引导, 经 GitHub Actions 云端编译打包成可刷写的 `boot.img`。

## 产物

| 文件 | 说明 |
|---|---|
| `boot.img` | 官方 4.19 内核 + HEY-W09 DTB + busybox initrd (fastboot 刷 boot 分区) |
| `rootfs.img` | Debian bookworm (GNOME + Firefox + apt/dpkg) ext4 镜像 (刷 data/rootfs 分区) |
| `rootfs.tar.xz` | rootfs 压缩包 |
| `initrd.cpio.gz` | initrd (busybox + init + WiFi 模块/固件) |

## 系统构成

- **内核**: 荣耀官方 Linux 4.19.157 (`Hendry-W09D_MagicUI6.1_Opensource`), 配置 `vendor/bengal_defconfig` (CONFIG_ARCH_KHAJE=y), **clang 交叉编译**(厂商官方 LLVM=1 工具链)
- **引导**: `boot.img` (header v2, os 12.0.0), initrd 由静态 busybox + init 组成
- **init 流程**: mount proc→/proc, sysfs→/sys, dev(优先 devtmpfs, 缺失则 tmpfs+mdev)→/dev → 加载 WiFi 模块(ath10k/ath11k/wcn36xx) → 定位 PARTLABEL=debian 根分区 → switch_root → systemd
- **rootfs**: Debian **bookworm** arm64, 包管理 **apt/dpkg**, 桌面 **GNOME** (gdm3), 浏览器 **Firefox (firefox-esr)**, NetworkManager, WiFi 固件, 中文字体; root 密码 `debian`

## 云端构建 (GitHub Actions)

推送或手动 `workflow_dispatch` 触发 `.github/workflows/build.yml`。在 `out/` 输出所有产物(可下载 artifact 或 tag Release)。

### 官方内核源码

源码来自 HONOR Open Source Release Center(`Hendry-W09D_MagicUI6.1_Opensource`, 551MB rar)。CI 从本仓库 Release 标签 `kernel-source` 拉取镜像(见 `scripts/fetch-kernel-official.sh`)。

### 官方 4.19 独立构建已修复的厂商源码问题

1. `drivers/power/reset/msm-poweroff.c`: `msm_restart_init()` 引用不存在的 `usb_update_thread` 线程 → 移除该引用
2. `scripts/gcc-wrapper.py`: python2 语法在 CI python3 下崩溃 → 替换为 python3 透传
3. `scripts/Makefile.lib`: 4.19 kbuild 缺 `-I$(obj)`, 驱动本地 trace 头无法解析 → 全局加 `-I$(obj)`
4. `CONFIG_BOOST_KILL`(Kconfig `default y`)引用缺失声明 → 强制关闭
5. 统一关闭 `-Werror` 告警当错 (GCC/clang 版本差异)

详见 `scripts/patch-vendor-419.sh` 与 `scripts/build-kernel-official.sh`。

## 刷机 (fastboot)

```bash
# 解锁 bootloader 后
fastboot flash boot boot.img
fastboot flash rootfs rootfs.img   # 分区名按机型实际布局调整
# 或: fastboot boot boot.img        # 临时引导验证
```

> 警告: 刷机有变砖风险, 请确认已解锁 bootloader 并做好备份。分区名/偏移以机型 stock boot.img 头为准(见 `docs/flash-guide.md`)。

## 待办 / 已知限制

- 触摸: 官方 4.19 内核 + HEY-W09 overlay DTB 应用后可望可用(正在接入 overlay 合并)
- WiFi: 模块加载已接入 initrd, 固件来自 linux-firmware
- GPU: Adreno 驱动随官方内核自带, GNOME Wayland 可加速
