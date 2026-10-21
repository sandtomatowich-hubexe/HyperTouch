#!/system/bin/sh
# Early-boot tweaks. These sysfs nodes are available well before
# boot_completed, unlike the touch/GPU/thermal ones in apply.sh.

MODDIR=${0%/*}
CONF="$MODDIR/settings.conf"
LOGTAG="HyperTouch"

# shellcheck disable=SC1090
. "$MODDIR/common.sh"

write() {
    if [ -w "$1" ]; then
        # Save the original BEFORE the first write. Without this, apply.sh
        # (which runs later in the same boot) would capture the already-
        # tweaked value as the "original".
        ht_save_node "$1"
        echo "$2" > "$1" 2>/dev/null
        log -p i -t "$LOGTAG" "applied $1 = $2"
    fi
}

# Defaults, overridden by settings.conf (parsed safely — never sourced).
VM_TWEAKS_ENABLED=0
SWAPPINESS=60
ht_load_conf "$CONF"

if [ "$VM_TWEAKS_ENABLED" = "1" ]; then
    write /proc/sys/vm/page-cluster 0
    write /sys/block/zram0/max_comp_streams 4
    write /proc/sys/vm/swappiness "$SWAPPINESS"
    write /proc/sys/vm/stat_interval 10
    # Scoped to zram/mmcblk/sd* queues only.
    for q in /sys/block/zram*/queue /sys/block/mmcblk*/queue /sys/block/sd*/queue; do
        [ -d "$q" ] || continue
        write "$q/read_ahead_kb" 128
    done
    write /proc/sys/kernel/sched_autogroup_enabled 1
else
    log -p i -t "$LOGTAG" "VM/ZRAM tweaks disabled (VM_TWEAKS_ENABLED=0 in settings.conf)."
fi

log -p i -t "$LOGTAG" "post-fs-data.sh completed."
