#!/system/bin/sh
# Early-boot tweaks. These sysfs nodes are available well before
# boot_completed, unlike the touch/GPU/thermal ones in apply.sh.

MODDIR=${0%/*}
CONF="$MODDIR/settings.conf"
LOGTAG="HyperTouch"

write() {
    if [ -w "$1" ]; then
        echo "$2" > "$1" 2>/dev/null
        log -p i -t "$LOGTAG" "applied $1 = $2"
    fi
}

# Defaults, overridden by settings.conf. These previously ran
# unconditionally on every device regardless of profile — swappiness
# 100 in particular is an aggressive, workload-dependent tradeoff
# (more swapping to ZRAM under memory pressure, more CPU spent
# compressing), not something safe to force on unknown/unconfirmed
# devices the way the touch/animation tweaks are.
VM_TWEAKS_ENABLED=0
SWAPPINESS=60
# shellcheck disable=SC1090
[ -f "$CONF" ] && . "$CONF"

if [ "$VM_TWEAKS_ENABLED" = "1" ]; then
    # -------------------------
    # Memory / ZRAM
    # -------------------------
    write /proc/sys/vm/page-cluster 0
    write /sys/block/zram0/max_comp_streams 4

    # -------------------------
    # VM
    # -------------------------
    write /proc/sys/vm/swappiness "$SWAPPINESS"
    write /proc/sys/vm/stat_interval 10

    # -------------------------
    # Block I/O
    # -------------------------
    # Scoped to zram/mmcblk/sd* queues only — the previous /sys/block/*
    # glob touched every writable block-device queue on the system,
    # including ones with no relation to this module's purpose (e.g.
    # loop devices, other storage controllers).
    for q in /sys/block/zram*/queue /sys/block/mmcblk*/queue /sys/block/sd*/queue; do
        [ -d "$q" ] || continue
        write "$q/read_ahead_kb" 128
    done

    # -------------------------
    # Kernel Scheduler
    # -------------------------
    write /proc/sys/kernel/sched_autogroup_enabled 1
else
    log -p i -t "$LOGTAG" "VM/ZRAM tweaks disabled (VM_TWEAKS_ENABLED=0 in settings.conf)."
fi

log -p i -t "$LOGTAG" "post-fs-data.sh completed."
