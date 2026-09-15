# HEY-W09 (荣耀平板8 / khaje) 9008 线刷 GPT 校准完全指南

## 1. 为什么必须校准

`hey-w09-edl.zip` 里的 `rawprogram0.xml` 描述"哪个文件写到 eMMC 的哪个扇区"。
高通 9008 刷写**不读分区表**,直接按扇区物理写入。如果 `start_sector` 写错,
会把 Kubuntu 刷到别的分区上(或覆盖掉系统/bootloader),轻则不开机,重则变砖(9008 通常可救)。

所以刷入前必须从**你自己的设备**读出真实 GPT,把 boot 和 userdata 分区的实际起始扇区填进去。

---

## 2. 获取设备真实 GPT 的三种方法(任选其一)

### 方法 A:TWRP / 橙狐 Rec(最简单,推荐)

设备刷入任意 TWRP/橙狐后,进入 Recovery → Advanced → Terminal,执行:

```sh
# 1) 查看所有分区起始扇区(最关键)
sgdisk --print /dev/block/mmcblk0

# 若没有 sgdisk,用 parted:
parted /dev/block/mmcblk0 unit s print

# 再不行,直接看内核分区映射(最通用):
cat /proc/partitions
ls -l /dev/block/by-name/
```

### 方法 B:已解锁/已 root 的 Android 系统

开机进 Android(开发者选项→USB调试开启),电脑上:

```sh
adb shell
su
cat /proc/partitions          # 看 mmcblk0pXX 的起始块(block)与大小
ls -l /dev/block/by-name/     # 看 boot / userdata 对应哪个 mmcblk0pXX
```

> 注意:`/proc/partitions` 显示的是 **block 数(512B/block)**,起始值直接就是扇区号,很方便。

### 方法 C:9008 模式 + qdl 读 GPT(无 TWRP 首选,推荐)

**适用**:没有 TWRP、没解锁、设备进不了系统的全部场景。
荣耀平板8 无官方解锁码,fastboot/TWRP 大概率不可用,这一条就是主路线。
9008 模式是硬件级通道,不依赖 bootloader 解锁;读 GPT 与刷写都用同一个 firehose 文件。

#### C-1. 获取 qdl 工具(Linux / WSL / macOS)

qdl 是开源工具(linux-msm/qdl),Ubuntu/WSL 上编译:

```sh
sudo apt-get install -y libxml2-dev libusb-1.0-0-dev build-essential git
git clone https://github.com/linux-msm/qdl.git
cd qdl && make          # 生成 ./qdl 可执行文件
```

Windows 用户建议装 WSL(Ubuntu)后按上面步骤;或使用 QFIL 的 "Read GPT"(见 C-4)。

#### C-2. 让设备进入 9008(EDL)模式

不需要解锁、不需要 TWRP,任选其一:

```sh
# 方式1: 组合键(多数 khaje 机型有效)
#   关机 -> 同时按住 音量上+下 -> 插 USB 数据线(保持按住直到电脑有反应)

# 方式2: 已开机的 Android 里 adb 重启(需要开发者选项已开)
adb reboot edl

# 方式3: 拆机短接 EDL 测试点(前面板都试不出时;khaje 主板上通常有 EDL 触点,
#        用镊子短接对应测试点到地,插线即可进 9008)
```

成功后设备管理器应出现 `Qualcomm HS-USB QDLoader 9008`(需要 QPST 驱动;
Windows 首次插上若显示感叹号,去 QPST 安装目录装 Qualcomm USB Driver,必要时禁用驱动签名)。

#### C-3. 用 qdl 读出真实 GPT

```sh
# 在 qdl 源码目录执行(prog_firehose_ddr.elf 放同目录):
./qdl --storage emmc --print-gpt prog_firehose_ddr.elf

# 或简短参数:
./qdl -s emmc -g prog_firehose_ddr.elf
```

输出形如(实际数字以你的设备为准):

```
LUN 0:
  #  start_sector   size_sectors   name
  1        4096         2048      xbl
  2        6144         2048      xbl_config
  ...
  8       24576        16384      boot
  ...
 41     2000000     45875200     userdata
```

把 **boot 的 start_sector** 和 **userdata 的 start_sector** 抄下来,进第 4 节填表。

> 若 `--print-gpt` 无输出或报错,先确认 9008 驱动正常、firehose 文件是 khaje/SM6225 专用。

#### C-4. 没有 Linux 时:QFIL 的 "Read GPT"

Windows 上打开 QFIL → Select Programmer 选 `prog_firehose_ddr.elf` →
Tools 菜单 → "Read GPT"(或 Flat Build 界面下用 Read Back 功能),
QFIL 会列出设备分区表,同样记下 boot / userdata 的起始扇区。

---

## 3. 看懂输出,找到两个数

以典型输出为例:

```
$ sgdisk --print /dev/block/mmcblk0
Number  Start (sector)  End (sector)  Size       Code  Name
1      4096             6143          1.0 MiB    8300  xbl
2      6144             8191          1.0 MiB    8300  xbl_config
...
8      24576            40959         8.0 MiB    8300  boot
...
26     655360           3932159       1.6 GiB    8300  system
...
36     1974272          4116480       1.0 GiB    8300  cache
...
41     2000000          47841279      21.8 GiB   8300  userdata
```

你只需要两行:

| 分区 | 起始扇区 | 说明 |
|---|---|---|
| **boot** | `24576` | 写 boot.img |
| **userdata** | `2000000` | 写 rootfs.img(Kubuntu 系统本体) |

> ⚠️ **不同批次/固件数字可能完全不同**,不要照抄本示例。必须用你自己设备的输出。
> userdata 在荣耀平板上通常很大(16-128GB),起始扇区取决于前面所有分区占用。

---

## 4. 把数字填进 rawprogram0.xml

用文本编辑器打开 `hey-w09-edl/rawprogram0.xml`,找到两个 `<program>` 行:

```xml
<program SECTOR_SIZE_IN_BYTES="512" file_sector_offset="0" filename="boot.img"
         label="boot" num_partition_sectors="40960"
         physical_partition_number="0" size_in_KB="65536"
         sparse="false" start_byte_as_string="hex:0x500000"/>

<program SECTOR_SIZE_IN_BYTES="512" file_sector_offset="0" filename="rootfs.img"
         label="userdata" num_partition_sectors="2000000"
         physical_partition_number="0" size_in_KB="16777216"
         sparse="false" start_byte_as_string="hex:0x3D09000"/>
```

### 需要修改的 3 个字段(每个分区):

| 字段 | 含义 | 怎么填 |
|---|---|---|
| `num_partition_sectors` | 起始扇区 | **直接填 GPT 里读到的 Start(sector)** |
| `physical_partition_number` | LUN/物理分区号 | 默认 0,若你设备 userdata 在 `mmcblk0pXX` 就是 0;若看到 `mmcblk0pXX` 的 LUN 信息不同再改 |
| `start_byte_as_string` | 起始字节(十六进制) | = 起始扇区 × 512,转十六进制,格式 `hex:0x…` |

### start_byte 快速换算(公式:扇区 × 512 = 字节)

| 起始扇区 | 字节 | 十六进制 |
|---|---|---|
| 24576 | 12,582,912 | `0xC00000` |
| 40960 | 20,971,520 | `0x1400000` |
| 2000000 | 1,024,000,000 | `0x3D09000` |

> 不会换算?不用手算——把 `rawprogram0.xml` 里 `start_byte_as_string` 的值也同步更新,
> 或者直接用 Python 一行算:`python3 -c "print(hex(24576*512))"`。

### size_in_KB 建议

- boot:`size_in_KB` 保持 `65536`(64MB 占位,实际 boot.img 只有 20MB,没问题)
- userdata:`size_in_KB` 建议填 **设备 userdata 分区实际大小**,可从 `sgdisk` 的 Size 列或
  `/proc/partitions` 算出;保守起见可保持占位,但不要小于 rootfs.img 实际大小(8.6GB ≈ 9,011,200 KB)

---

## 5. 修改后自检(刷前必做)

```xml
<!-- 以 boot 起始扇区 24576 为例,修改后应长这样: -->
<program ... filename="boot.img" label="boot"
         num_partition_sectors="24576"
         physical_partition_number="0" size_in_KB="65536"
         sparse="false" start_byte_as_string="hex:0xC00000"/>
```

自检清单:
- [ ] `num_partition_sectors` = 设备 GPT 的 Start(sector)(注意:这是**起始扇区**,不是大小!)
- [ ] `start_byte_as_string` = 起始扇区 × 512 的十六进制
- [ ] 两个分区数字都来自**你自己的设备**,不是示例
- [ ] `size_in_KB` ≥ 镜像实际大小

---

## 6. 开始刷入

1. 设备进 9008(关机,音量上+下同时插 USB;或 root 后 `adb reboot edl`),电脑出现 `Qualcomm HS-USB QDLoader 9008`
2. 打开 QFIL → Select Programmer → 选 `prog_firehose_ddr.elf`(khaje 专用,从原厂固件提取)
3. Flat Build → 添加修改后的 `rawprogram0.xml` 和 `patch0.xml`
4. Download → 等待完成,设备自动重启进 Kubuntu(登录 `root / debian`)

---

## 7. 常见问题

| 现象 | 原因 | 处理 |
|---|---|---|
| QFIL 报 "Sahara protocol error" | firehose 文件版本/型号不匹配 | 换 khaje/SM6225 专用 firehose |
| 刷完不开机,黑屏 | 扇区写错,覆盖了 bootloader/系统 | 9008 重新进 EDL,恢复原厂 GPT 再刷 |
| 刷完进 Android 但没 Linux | boot 扇区写错,Android 的 boot 被覆盖或没生效 | 重新校准 boot 扇区重刷 |
| rootfs.img 太大刷不进 | userdata size_in_KB 小于镜像 | 增大 size_in_KB 或先扩容 userdata |
| 找不到 9008 驱动 | 缺 Qualcomm USB 驱动 | 装 QPST 自带驱动,或驱动签名禁用后安装 |
| qdl 连不上设备 | 驱动没装好 / firehose 不匹配 | 重装 QPST 驱动;确认 firehose 是 khaje/SM6225 专用 |
| 进不了 9008(组合键无效) | 机型批次差异 | 试 `adb reboot edl`;或拆机短接 EDL 测试点 |

> 最后的保底:只要 9008 模式还能进、firehose 还在,砖就能救——从原厂固件全量刷回即可。


---

## 8. 无 TWRP / 无 Linux 的 Windows 用户:QFIL 专版完整流程

适用:只有 Windows 电脑、设备无 TWRP、无 root、无解锁码。整条路全程用 QFIL(Qualcomm 官方工具)完成。

### 8.1 准备软件

```text
1. QPST 工具包(含 QFIL) — Qualcomm 官方,搜 "QPST download"
   安装后: C:\Program Files (x86)\Qualcomm\QPST\bin\QFIL.exe
2. 高通 USB 驱动 — QPST 自带;若设备管理器 9008 显示感叹号,
   在驱动属性里"更新驱动->手动->从 QPST 驱动目录"安装,
   必要时开机按 F8 禁用驱动签名强制安装
```

### 8.2 从官方固件包提取 firehose(必需,别跳过)

```text
1. 下载荣耀平板8 (HEY-W09) 官方固件包:
   荣耀官网支持页 / 固件站搜索 "HEY-W09 固件" 得到 update.app 或 .hwr 包
2. 解包工具任选:
   - HuaweiUpdateExtractor (Windows GUI, 最省事)
   - 或 Python 的 hwupdate 解包脚本
3. 解包后找: prog_firehose_ddr.elf 或含 "firehose" 字样的文件
   (可能在根目录或 recovery 相关目录)
4. 验证型号: 文件名/内部应含 khaje 或 SM6225 相关标识
5. 把 prog_firehose_ddr.elf 单独放一个文件夹, 例如 C:\hey-w09\
```

> 如果官方包解不出 firehose(部分荣耀包只含 update.app 系统镜像),
> 换思路: 下载同芯片(骁龙680/khaje)其它品牌机型的线刷包,
> 提取其中的 prog_firehose_ddr.elf(跨品牌同名加载器通常兼容, 需实测)。

### 8.3 设备进 9008

```text
关机 -> 同时按住 音量上 + 音量下 -> 插 USB 线(保持按住直到电脑有反应)
设备管理器出现 "Qualcomm HS-USB QDLoader 9008" 即成功
```

> 组合键无效时: 设备已开机可试 `adb reboot edl`(需 USB 调试);
> 再不行需拆机, 在主板 EDL 测试点短接(镊子点到地)再插线。

### 8.4 QFIL 读 GPT(代替 qdl, 不需要命令行)

```text
1. 打开 QFIL
2. Select Programmer -> 选 C:\hey-w09\prog_firehose_ddr.elf
   加载成功后 QFIL 显示 "Sahara protocol" 完成并连上设备
3. 菜单 Tools -> "Read GPT" (或 Flat Build 界面勾选 Read GPT)
4. 弹出窗口显示设备分区表, 找到:
     boot     的 start sector
     userdata 的 start sector
   截图保存! 这两个数字就是校准依据
```

### 8.5 (可选)用 QFIL Read Back 提取/备份原厂固件

```text
1. Tools -> Read Back
2. Add -> 填分区起始扇区 + 扇区长度(从 8.4 的 GPT 表抄)
   boot 示例: Start 24576, Sectors 16384
   userdata 示例: Start 2000000, Sectors 45875200(填完整分区)
3. 生成 ReadBack.xml, 点 "Read Back" 开始导出
4. 保存的 .bin/.img 就是原厂分区镜像(备份/提取用)
```

> Read Back 也可以直接整片备份(GPT 表里的总扇区数),
> 这就是"从 9008 提取固件"的标准做法。

### 8.6 校准 rawprogram0.xml 并刷入

```text
1. 用记事本打开 hey-w09-edl/rawprogram0.xml
2. 把 8.4 读到的两个 start sector 填入:
   boot.img 行    -> num_partition_sectors = boot 起始扇区
   rootfs.img 行  -> num_partition_sectors = userdata 起始扇区
   start_byte_as_string = hex(起始扇区 x 512)
   不会换算: 用 Windows 计算器(程序员模式) 或 python3 -c "print(hex(24576*512))"
3. QFIL: Flat Build -> 添加 rawprogram0.xml + patch0.xml
4. 点 Download, 等待完成, 设备重启进 Kubuntu (登录 root / debian)
```

### 8.7 Windows 常见坑

| 现象 | 原因 | 处理 |
|---|---|---|
| 9008 设备管理器是黄叹号 | 驱动没装/签名拦截 | 禁用驱动签名后装 QPST 驱动 |
| QFIL 卡在 Sahara | firehose 与设备不匹配 | 换 khaje/SM6225 专用 firehose |
| Read GPT 空白/报错 | firehose 无读权限或版本旧 | 换新版本 firehose 重试 |
| Read Back 导出中断 | USB 线/口供电不稳 | 换原装线、插主板 USB 口 |
