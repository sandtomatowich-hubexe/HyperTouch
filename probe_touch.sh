#!/system/bin/sh
# Read-only discovery tool. NOT run automatically by the module.
#
# Run this once as root — e.g. `adb shell su -c sh /sdcard/probe_touch.sh`,
# or from a terminal app after `su` — to find out which touch-tuning
# sysfs nodes actually exist on your kernel build. It only cat's files,
# it never writes anything.
#
# Paste the output back and the real node names can be wired into
# settings.conf's TOUCH_SENSITIVITY_PATH / TOUCH_EDGE_PATH /
# PALM_REJECT_PATH.

dump_dir() {
    dir="$1"
    [ -d "$dir" ] || return
    echo "--- $dir ---"
    for f in "$dir"/*; do
        [ -f "$f" ] || continue
        [ -r "$f" ] || { echo "$f (write-only or unreadable)"; continue; }
        val=$(cat "$f" 2>/dev/null)
        echo "$f = $val"
    done
}

echo "== Goodix touch device =="
dump_dir /sys/devices/platform/goodix_ts.0
for d in /sys/devices/platform/goodix_ts.0/input/input*; do
    dump_dir "$d"
done

echo
echo "== xiaomi-touch class (if present on this kernel) =="
for d in /sys/class/xiaomi-touch/*; do
    dump_dir "$d"
done

echo
echo "== touchpanel proc interface (if present) =="
if [ -d /proc/touchpanel ]; then
    ls -la /proc/touchpanel
else
    echo "not present"
fi

echo
echo "== done =="
