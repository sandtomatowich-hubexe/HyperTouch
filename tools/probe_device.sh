#!/system/bin/sh
# HyperTouch device probe — READ-ONLY.
# Collects everything apply.sh would touch on a device, so a new profile
# (e.g. rodin / POCO X7 Pro) can be written from real data instead of
# guesses. It never writes to any node and never changes any setting.
#
# Run as root, from a terminal app or adb:
#   su -c "sh /sdcard/probe_device.sh" > /sdcard/hypertouch_probe.txt 2>&1
# then send hypertouch_probe.txt.
#
# Contains: device model, ROM/kernel version, hardware node paths and
# values, display refresh modes. Contains NO personal data (no app list,
# accounts, serials, IMEI or location).

sec() { echo; echo "===== $1 ====="; }
val() { # path -> "path = value  [writable|read-only]"
    [ -e "$1" ] || { echo "$1  (missing)"; return; }
    if [ -w "$1" ]; then m=writable; else m=read-only; fi
    echo "$1 = $(cat "$1" 2>&1 | head -3 | tr '\n' ' ')  [$m]"
}

sec "DEVICE"
echo "codename : $(getprop ro.product.device)"
echo "model    : $(getprop ro.product.model)"
echo "name     : $(getprop ro.product.name)"
echo "soc      : $(getprop ro.soc.manufacturer) $(getprop ro.soc.model)"
echo "platform : $(getprop ro.board.platform) / $(getprop ro.hardware)"
echo "android  : $(getprop ro.build.version.release) (sdk $(getprop ro.build.version.sdk))"
echo "rom      : $(getprop ro.mi.os.version.name) $(getprop ro.mi.os.version.incremental)"
echo "build    : $(getprop ro.build.display.id)"
echo "kernel   : $(uname -r)"
echo "selinux  : $(getenforce 2>&1)"
echo "root     : uid=$(id -u)"

sec "CPU CLUSTERS (apply.sh assumes policies 0 4 7)"
for p in /sys/devices/system/cpu/cpufreq/policy*; do
    [ -d "$p" ] || continue
    echo "-- $p"
    echo "   related_cpus=$(cat "$p/related_cpus" 2>/dev/null)  min=$(cat "$p/cpuinfo_min_freq" 2>/dev/null)  max=$(cat "$p/cpuinfo_max_freq" 2>/dev/null)"
    echo "   governor=$(cat "$p/scaling_governor" 2>/dev/null)  available=$(cat "$p/scaling_available_governors" 2>/dev/null)"
    if [ -d "$p/schedutil" ]; then
        echo "   schedutil tunables:"
        for f in "$p"/schedutil/*; do [ -f "$f" ] && val "$f" | sed 's/^/     /'; done
    else
        echo "   (no schedutil dir)"
    fi
done

sec "TOUCH PANEL (report-rate node used by HyperTouch)"
echo "-- known paths"
val /sys/devices/platform/goodix_ts.0/switch_report_rate
val /sys/devices/platform/goodix_ts.0/goodix_ts_report_rate
echo "-- touch-related entries under /sys/devices/platform (names only)"
ls /sys/devices/platform 2>/dev/null | grep -i -E "touch|ts|goodix|focal|fts|novatek|nvt|himax|synaptics|xiaomi" | head -20
echo "-- touch input devices"
for n in /sys/class/input/input*/name; do
    echo "$n = $(cat "$n" 2>/dev/null)"
done | grep -i -E "touch|ts|goodix|focal|fts|nvt|himax|synaptics" | head -10
echo "-- rate/mode-like nodes inside touch dirs"
for d in /sys/devices/platform/goodix_ts.0 /sys/devices/platform/*touch* /sys/devices/platform/*fts* /sys/devices/platform/*nvt* /proc/touchpanel; do
    [ -d "$d" ] || continue
    for f in "$d"/*rate* "$d"/*sampl* "$d"/*game* "$d"/*mode*; do
        [ -e "$f" ] && val "$f"
    done
done

sec "GPU (apply.sh assumes a Mali devfreq at 13000000.mali)"
for g in /sys/devices/platform/soc/*.mali/devfreq/*.mali /sys/devices/platform/*.mali/devfreq/*.mali /sys/class/devfreq/*mali* /sys/class/kgsl/kgsl-3d0/devfreq; do
    [ -d "$g" ] || continue
    echo "-- $g"
    for f in governor min_freq max_freq cur_freq available_frequencies available_governors; do
        [ -e "$g/$f" ] && val "$g/$f"
    done
done

sec "THERMAL / BATTERY"
val /sys/devices/virtual/thermal/thermal_message/sconfig
for b in /sys/class/power_supply/*/temp; do [ -e "$b" ] && val "$b"; done

sec "VM / BLOCK NODES"
for n in /proc/sys/vm/page-cluster /sys/block/zram0/max_comp_streams /proc/sys/vm/swappiness /proc/sys/vm/stat_interval /proc/sys/kernel/sched_autogroup_enabled; do val "$n"; done
for q in /sys/block/zram*/queue /sys/block/mmcblk*/queue /sys/block/sd*/queue; do
    [ -d "$q" ] && val "$q/read_ahead_kb"
done

sec "DISPLAY / REFRESH RATE"
echo "supported modes (fps values from dumpsys display):"
dumpsys display 2>/dev/null | grep -oE '(fps|refreshRate)=[0-9.]+' | sort -u | head -20
echo "settings: min_refresh_rate=$(settings get system min_refresh_rate 2>&1)  peak_refresh_rate=$(settings get system peak_refresh_rate 2>&1)"
echo "settings: deviceLevelList=$(settings get system deviceLevelList 2>&1)  miui_home_animation_rate=$(settings get system miui_home_animation_rate 2>&1)"

sec "POWERKEEPER"
echo "package present : $(pm path com.miui.powerkeeper 2>&1 | head -1)"
echo "package disabled: $(pm list packages -d 2>/dev/null | grep -c 'com.miui.powerkeeper')  (1 = disabled)"
dumpsys package com.miui.powerkeeper 2>/dev/null | grep -i "PowerStateMachineService" | head -3
echo "launcher package: $(pm path com.miui.home 2>&1 | head -1)"

sec "DONE"
echo "Read-only probe finished. Nothing was changed."
