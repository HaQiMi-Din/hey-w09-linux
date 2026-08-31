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

echo ">> vendor patches done"
