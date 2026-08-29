#!/system/bin/sh
# Early-boot tweaks. These sysfs nodes are available well before
# boot_completed, unlike the touch/GPU/thermal ones in apply.sh.

LOGTAG="HyperTouch"

write() {
    if [ -w "$1" ]; then
        echo "$2" > "$1" 2>/dev/null
        log -p i -t "$LOGTAG" "applied $1 = $2"
    fi
}

# -------------------------
# Memory / ZRAM
# -------------------------
write /proc/sys/vm/page-cluster 0
write /sys/block/zram0/max_comp_streams 4

# -------------------------
# VM
# -------------------------
write /proc/sys/vm/swappiness 100
write /proc/sys/vm/stat_interval 10

# -------------------------
# Block I/O
# -------------------------
for q in /sys/block/*/queue; do
    write "$q/read_ahead_kb" 128
done

# -------------------------
# Kernel Scheduler
# -------------------------
write /proc/sys/kernel/sched_autogroup_enabled 1

log -p i -t "$LOGTAG" "post-fs-data.sh completed."
