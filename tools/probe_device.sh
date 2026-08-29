#!/system/bin/sh
# Read-only discovery tool for the device-profile framework in apply.sh.
# NOT run automatically by the module. Run once as root when trying
# HyperTouch on a device other than duchamp, to gather what's needed
# for a new case-statement entry (CPU cluster layout, GPU governor
# node, thermal node). Pair with probe_touch.sh for the touch side.
#
#   adb shell su -c "sh /sdcard/probe_device.sh" > device_profile.txt

echo "== Device =="
echo "device  : $(getprop ro.product.device)"
echo "model   : $(getprop ro.product.model)"
echo "android : $(getprop ro.build.version.release)"
echo "kernel  : $(uname -r)"

echo
echo "== CPU cluster layout =="
for p in /sys/devices/system/cpu/cpufreq/policy*; do
    [ -d "$p" ] || continue
    cpus=$(cat "$p/related_cpus" 2>/dev/null)
    cur=$(cat "$p/scaling_governor" 2>/dev/null)
    echo "$p  cpus=[$cpus]  governor=$cur"
done

echo
echo "== GPU governor =="
for g in /sys/devices/platform/soc/*.mali/devfreq/*.mali/governor /sys/class/kgsl/kgsl-3d0/devfreq/governor; do
    [ -f "$g" ] || continue
    echo "$g = $(cat "$g" 2>/dev/null)"
done

echo
echo "== Thermal =="
[ -f /sys/devices/virtual/thermal/thermal_message/sconfig ] && \
    echo "/sys/devices/virtual/thermal/thermal_message/sconfig = $(cat /sys/devices/virtual/thermal/thermal_message/sconfig 2>/dev/null)"

echo
echo "== Battery temp node =="
for b in /sys/class/power_supply/*/temp; do
    [ -f "$b" ] || continue
    echo "$b = $(cat "$b" 2>/dev/null)"
done

echo
echo "== done — also run probe_touch.sh for the touch driver side =="
