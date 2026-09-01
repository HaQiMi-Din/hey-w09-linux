#!/usr/bin/env bash
# 对荣耀官方 4.19 GKI 内核源码打补丁, 修复独立(非 Android 构建系统)构建时的厂商源码缺陷。
# 所有问题均已从官方源码定位根因:
#  1) msm-poweroff.c: msm_restart_init() 无条件引用 usb_update_thread/update_task,
#     该荣耀私有 OTA 线程函数在本发行版源码中不存在, 属厂商残留 -> 移除引用。
#  2) scripts/gcc-wrapper.py: 用 python2 语法编写, 在 python3 环境(CI)崩溃,
#     导致 kconfig 无法探测编译器 -> 替换为 python3 透传。
#  3) Makefile.lib: 4.19 kbuild 的 c/a/cpp_flags 未带 -I$(obj),
#     驱动本地 trace 头(TRACE_INCLUDE_PATH=.)无法解析 -> 全局加 -I$(obj)。
set -euo pipefail
cd "$(dirname "$0")/.."

KERNEL_SRC="${KERNEL_SRC:-kernel}"
cd "$KERNEL_SRC"

echo ">> [patch 1/3] msm-poweroff.c: 移除缺失的 usb_update 线程引用"
python3 - <<'PYEOF'
p = 'drivers/power/reset/msm-poweroff.c'
s = open(p).read()
old = '''static int __init msm_restart_init(void)
{
	update_task = kthread_run(usb_update_thread, NULL, "usb_update");
	if (IS_ERR(update_task))
		pr_err("usb_update thread run error\\n");

	return platform_driver_register(&msm_restart_driver);
}'''
new = '''static int __init msm_restart_init(void)
{
	/* usb_update_thread 为荣耀私有 OTA 升级线程(源码缺失), 本发行版不使用 */
	return platform_driver_register(&msm_restart_driver);
}'''
assert old in s, "msm-poweroff.c patch anchor not found"
open(p, 'w').write(s.replace(old, new))
print("  OK msm-poweroff.c patched")
PYEOF

echo ">> [patch 2/3] gcc-wrapper.py: python2 -> python3 透传"
cat > scripts/gcc-wrapper.py <<'PYEOF'
#!/usr/bin/env python3
# Passthrough: 直接执行真实编译器, 保留 Qualcomm Makefile 对 CC 的包装调用。
import sys, subprocess
sys.exit(subprocess.call(sys.argv[1:]))
PYEOF
chmod +x scripts/gcc-wrapper.py
echo "  OK gcc-wrapper.py replaced"

echo ">> [patch 3/3] Makefile.lib: c/a/cpp_flags 加 -I\$(obj) (修复 TRACE_INCLUDE_PATH=.)"
if grep -q 'NOSTDINC_FLAGS' scripts/Makefile.lib; then
    sed -i 's/\$(NOSTDINC_FLAGS) \$(LINUXINCLUDE)/\$(NOSTDINC_FLAGS) -I\$(obj) \$(LINUXINCLUDE)/g' scripts/Makefile.lib
    echo "  OK Makefile.lib patched"
else
    echo "  SKIP (NOSTDINC_FLAGS 不存在)"
fi

echo ">> [patch 4/4] dsi_display.c: 无条件 lcdkit ESD 调用加 CONFIG_LCD_KIT_DRIVER 保护"
python3 - <<'PYEOF'
p = 'techpack/display/msm/dsi/dsi_display.c'
s = open(p).read()
old = '''	} else if (status_mode == ESD_MODE_PANEL_GPIO) {
		rc = lcd_kit_dual_gpio_esd_check();
	} else {'''
new = '''	} else if (status_mode == ESD_MODE_PANEL_GPIO) {
#ifdef CONFIG_LCD_KIT_DRIVER
		rc = lcd_kit_dual_gpio_esd_check();
#else
		DSI_WARN("GPIO ESD check unsupported without lcdkit\\n");
		panel->esd_config.esd_enabled = false;
#endif
	} else {'''
assert old in s, "dsi_display.c patch anchor not found"
open(p, 'w').write(s.replace(old, new))
print("  OK dsi_display.c patched")
PYEOF
echo ">> [patch 5/5] DTS: 修复 pm7250b 变体与 pmi632 的重复 label (smb5_vbus/bcl_soc)"
python3 - <<'PYEOF'
def patch(p, subs):
    s = open(p).read()
    for old, new in subs:
        assert old in s, f"anchor not found in {p}: {old[:50]!r}"
        s = s.replace(old, new)
    open(p, 'w').write(s)
    print(f"  OK {p}")

patch('arch/arm64/boot/dts/vendor/qcom/pm7250b.dtsi', [
    ('bcl_soc:bcl-soc {', 'pm7250b_bcl_soc:bcl-soc {'),
    ('thermal-sensors = <&bcl_soc>', 'thermal-sensors = <&pm7250b_bcl_soc>'),
])
for _f in ['khaje-idp-pm7250b.dtsi', 'khaje-qrd-pm7250b.dtsi', 'khaje-atp.dtsi']:
    patch(f'arch/arm64/boot/dts/vendor/qcom/{_f}', [
        ('smb5_vbus: qcom,smb5-vbus {', 'pm7250b_smb5_vbus: qcom,smb5-vbus {'),
        ('vbus-supply = <&smb5_vbus>', 'vbus-supply = <&pm7250b_smb5_vbus>'),
    ])
PYEOF
echo ">> [patch 6/6] DTS: DTC_FLAGS 加 -Wno-duplicate_label + khaje.dtb 加入构建"
python3 - <<'PYEOF'
# 1) arch/arm64/Makefile: 厂商导出 DTC_FLAGS := -@, 新版 dtc 在 -@ 下把 duplicate_label
#    当 ERROR (khaje-idp/qrd/atp 等测试板同时挂 pm7250b+pmi632 导致标签重复) -> 追加忽略
p = 'arch/arm64/Makefile'
s = open(p).read()
old_m = 'export DTC_FLAGS := -@'
new_m = 'export DTC_FLAGS := -@ -Wno-duplicate_label'
assert old_m in s, "arch/arm64/Makefile DTC_FLAGS anchor not found"
open(p, 'w').write(s.replace(old_m, new_m))
print("  OK arch/arm64/Makefile DTC_FLAGS")

# 2) qcom/Makefile: 把 khaje.dtb (真实设备基底, HEY_W09_VA overlay 合并用) 加进 dtb-y
p = 'arch/arm64/boot/dts/vendor/qcom/Makefile'
s = open(p).read()
old_m = 'dtb-$(CONFIG_ARCH_KHAJE) += khaje-idp.dtb \\'
new_m = 'dtb-$(CONFIG_ARCH_KHAJE) += khaje.dtb \\' + chr(10) + '\t\tkhaje-idp.dtb \\'
assert old_m in s, "khaje dtb-y anchor not found"
open(p, 'w').write(s.replace(old_m, new_m))
print("  OK qcom/Makefile khaje.dtb added")
PYEOF
echo ">> vendor patches done"
echo ">> [patch 7/7] 链接期修复: selinux_state 去 rtic 段 + power_nv_write stub"
python3 - <<'PYEOF'
# 1) selinux_state 被厂商标进 .bss.rtic, 该段放置导致 ADRP 重定位截断 -> 去掉属性回普通 .bss
p = 'security/selinux/hooks.c'
s = open(p).read()
old_m = 'struct selinux_state selinux_state __rticdata;'
new_m = 'struct selinux_state selinux_state;'
assert old_m in s, "hooks.c selinux_state anchor not found"
open(p, 'w').write(s.replace(old_m, new_m))
print("  OK hooks.c selinux_state 去 __rticdata")

# 2) power_nv_write 真源在 honor_platform_6225 (受 CONFIG_HONOR_POWER 门控未编译),
#    coul_calibration 无条件引用 -> 补 weak stub (电量校准持久化非必需)
p = 'drivers/honor_power/cc_coul/coul_calibration.c'
s = open(p).read()
old_m = 'static int coul_cali_save_data(void *dev_data)'
new_m = ('#ifndef CONFIG_HONOR_POWER\n'
         '__weak int power_nv_write(enum power_nv_type type, const void *data, uint32_t data_len)\n'
         '{\n'
         '\t/* power_nv 模块未编译, 电量校准数据不持久化 */\n'
         '\treturn 0;\n'
         '}\n'
         '#endif\n'
         'static int coul_cali_save_data(void *dev_data)')
assert old_m in s, "coul_calibration.c anchor not found"
open(p, 'w').write(s.replace(old_m, new_m))
print("  OK coul_calibration.c power_nv_write weak stub")
PYEOF
echo ">> vendor patches done"
echo ">> [patch 8/8] hiview 遥测模块实现缺失 -> 恢复 cam_hiview + 提供 no-op stub"
python3 - <<'PYEOF'
# 1) 恢复 cam_hiview 编译并加入 hiview_stub.o (cam_dmd_util 等依赖 cam_hiview_* API)
p = 'techpack/camera/drivers/Makefile'
s = open(p).read()
a = 'obj-$(CONFIG_SPECTRA_CAMERA)      += cam_hiview/cam_hiview.o'
if 'hiview_stub.o' not in s:
    assert a in s, "cam_hiview Makefile anchor not found"
    s = s.replace(a, a + '\nobj-$(CONFIG_SPECTRA_CAMERA)      += cam_hiview/hiview_stub.o')
    open(p, 'w').write(s)
    print("  OK cam_hiview + hiview_stub.o 已加入")
else:
    print("  OK 已含 hiview_stub.o")

# 2) 写 no-op stub (hiview 仅事件上报, stub 不影响功能)
stub = (
    '/*\n'
    ' * hiview 遥测模块(honor 私有内核组件)未随开源 Release 提供实现。\n'
    ' * 独立构建下提供 no-op 实现, 保证 cam_hiview 等调用方可链接。\n'
    ' */\n'
    '#include <linux/types.h>\n'
    '#include <log/hiview_hievent.h>\n'
    '\n'
    'struct hiview_hievent *hiview_hievent_create(unsigned int event_id)\n'
    '{\n'
    '\treturn NULL;\n'
    '}\n'
    '\n'
    'int hiview_hievent_report(struct hiview_hievent *event)\n'
    '{\n'
    '\treturn 0;\n'
    '}\n'
    '\n'
    'void hiview_hievent_destroy(struct hiview_hievent *event)\n'
    '{\n'
    '}\n'
    '\n'
    'int hiview_hievent_put_string(struct hiview_hievent *event,\n'
    '\tconst char *key, const char *value)\n'
    '{\n'
    '\treturn 0;\n'
    '}\n'
    '\n'
    'int hiview_hievent_put_integral(struct hiview_hievent *event,\n'
    '\tconst char *key, long long value)\n'
    '{\n'
    '\treturn 0;\n'
    '}\n'
    '\n'
    'int hiview_hievent_set_time(struct hiview_hievent *event, long long seconds)\n'
    '{\n'
    '\treturn 0;\n'
    '}\n'
    '\n'
    'int hiview_hievent_add_file_path(struct hiview_hievent *event,\n'
    '\tconst char *path)\n'
    '{\n'
    '\treturn 0;\n'
    '}\n'
)
open('techpack/camera/drivers/cam_hiview/hiview_stub.c', 'w').write(stub)
print("  OK hiview_stub.c 已写入")
PYEOF
echo ">> vendor patches done"
echo ">> [patch 9/9] 修复 modpost .mod.o 编译: c_flags 在子make中为空 -> 显式补全内核编译标志"
python3 - <<'PYEOF'
p = 'scripts/Makefile.modpost'
s = open(p).read()
old_m = ('      cmd_cc_o_c = $(CC) $(c_flags) $(KBUILD_CFLAGS_MODULE) $(CFLAGS_MODULE) \\\n'
         '\t\t   -c -o $@ $<')
# 显式补全: -D__KERNEL__ (uapi compat 符号必需) + autoconf.h (CONFIG_*) + 全部 include 路径
new_m = ('      cmd_cc_o_c = $(CC) $(c_flags) $(KBUILD_CPPFLAGS) -D__KERNEL__ \\\n'
         '\t\t   -include $(objtree)/include/generated/autoconf.h \\\n'
         '\t\t   -I$(srctree)/arch/$(SRCARCH)/include \\\n'
         '\t\t   -I$(objtree)/arch/$(SRCARCH)/include/generated \\\n'
         '\t\t   -I$(srctree)/arch/$(SRCARCH)/include/uapi \\\n'
         '\t\t   -I$(objtree)/arch/$(SRCARCH)/include/generated/uapi \\\n'
         '\t\t   -I$(srctree)/include -I$(objtree)/include/generated \\\n'
         '\t\t   -I$(srctree)/include/uapi -I$(objtree)/include/generated/uapi \\\n'
         '\t\t   $(KBUILD_CFLAGS_MODULE) $(CFLAGS_MODULE) -c -o $@ $<')
assert old_m in s, "modpost anchor not found"
open(p, 'w').write(s.replace(old_m, new_m))
print("  OK modpost .mod.o 已补全 -D__KERNEL__ + autoconf.h + include 路径")
PYEOF
echo ">> vendor patches done"
