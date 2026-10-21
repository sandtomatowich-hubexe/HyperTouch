#!/system/bin/sh
# Restores the system to its pre-HyperTouch state on removal.
#
# Sysfs tweaks reset on their own at the next boot, but PowerKeeper state,
# Settings-provider values and Priority-App changes (Doze whitelist,
# AppOps, standby bucket) persist independently of the module, so they
# must be explicitly reverted. Each is restored to its SAVED original
# value (see common.sh), never to a guessed "stock" value.
#
# NOTE: root managers normally run uninstall.sh very early at the NEXT
# boot, before the package manager / settings service exist, so `pm`,
# `settings`, `cmd` and `dumpsys` would silently do nothing. In that case
# the state is snapshotted and the restore is deferred to a background job
# that waits for sys.boot_completed. If the system is already up (manager
# ran it live) the restore happens immediately.
#
# HyperTouch no longer changes persist.sys.miui_optimization or animation
# scales, so this script no longer forces either of them.

MODDIR=${0%/*}
CONF="$MODDIR/settings.conf"
LOGTAG="HyperTouch"

# shellcheck disable=SC1090
. "$MODDIR/common.sh"

PRIORITY_APPS=
TG_LAG_FIX=0
ht_load_conf "$CONF"
ht_watch_stop        # stop the keep-applied watcher if it is running

SNAP="/data/local/tmp/hypertouch_uninstall.$$"
LIVE=0
[ "$(getprop sys.boot_completed)" = "1" ] && LIVE=1

if [ "$LIVE" != "1" ]; then
    # The module directory is deleted right after this script returns, so
    # keep our own copy of the state for the deferred job.
    mkdir -p "$SNAP" 2>/dev/null
    if [ -d "$MODDIR/.state" ]; then
        cp -rp "$MODDIR/.state" "$SNAP/state" 2>/dev/null
    fi
    mkdir -p "$SNAP/state" 2>/dev/null
    HT_STATE_DIR="$SNAP/state"
fi

ht_uninstall_restore() {
    ht_pk_restore_pkg
    ht_pk_restore_comp

    ht_restore_setting system deviceLevelList settings_deviceLevelList
    ht_restore_setting system miui_home_animation_rate settings_miui_home_animation_rate
    ht_restore_setting system min_refresh_rate settings_min_refresh_rate
    ht_restore_setting system peak_refresh_rate settings_peak_refresh_rate

    # Everything that has a saved capture…
    ht_prio_restore_all
    # …plus anything the config lists (covers state lost to an old update).
    set -f
    apps="$PRIORITY_APPS"
    [ "$TG_LAG_FIX" = "1" ] && apps="$apps org.telegram.messenger"
    for pkg in $apps; do
        ht_valid_pkg "$pkg" && ht_prio_restore "$pkg"
    done
    set +f

    if [ "$LIVE" = "1" ]; then
        # System is up, so kernel nodes haven't been reset by a reboot yet.
        ht_restore_all_nodes >/dev/null
        ht_restore_report_rate >/dev/null
    fi
    log -p i -t "$LOGTAG" "uninstall: restored original state."
}

if [ "$LIVE" = "1" ]; then
    ht_uninstall_restore
else
    (
        i=0
        while [ "$(getprop sys.boot_completed)" != "1" ]; do
            i=$((i + 1))
            [ "$i" -gt 200 ] && break      # ~10 min cap
            sleep 3
        done
        sleep 10   # let package manager / settings settle
        ht_uninstall_restore
        rm -rf "$SNAP" 2>/dev/null
    ) >/dev/null 2>&1 &
fi
exit 0
