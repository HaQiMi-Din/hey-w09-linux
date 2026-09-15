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

### 方法 C:9008 模式 + firehose(无法进系统时)

连接 9008 后用 QFIL/qdl 的 `qdl --storage emmc --print-gpt`(qdl 工具)或
QFIL 的 "Read GPT" 功能导出分区表。此方法在设备完全黑屏时也能用,但需要先有 firehose 文件。

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

> 最后的保底:只要 9008 模式还能进、firehose 还在,砖就能救——从原厂固件全量刷回即可。
