#!/system/bin/sh
# HyperTouch management layer.
#
# With no arguments: re-applies current settings.conf (this is what
# runs when you tap "Action" in KernelSU/Magisk manager — same as
# always). With arguments: a small CLI for scripting/terminal use.
# Both paths — and the WebUI — all read/write the same settings.conf
# and call the same apply.sh, so nothing can get out of sync.
#
# Usage:
#   action.sh                     re-apply current settings
#   action.sh status              show current settings + device profile
#   action.sh enable <feature>    boost | powerkeeper | battery-spoof |
#                                 fast-cpu | gpu-floor | powerkeeper-full |
#                                 parallel-anim | launcher-anim | force-120hz |
#                                 tg-fix
#   action.sh disable <feature>   (same feature names)
#   action.sh reset               restore settings.conf to shipped defaults
#   action.sh revert              temporarily undo tweaks (settings.conf kept)
#   action.sh help                show this text

MODDIR=${0%/*}
CONF="$MODDIR/settings.conf"
DEFAULT_CONF="$MODDIR/settings.conf.default"

# shellcheck disable=SC1090
. "$MODDIR/lock.sh"
# shellcheck disable=SC1090
. "$MODDIR/common.sh"

# Reads a value WITHOUT its surrounding quotes (the WebUI writes
# PRIORITY_APPS="a b"; the quotes are not part of the value).
conf_get() {
    _cg=$(grep "^$1=" "$CONF" 2>/dev/null | tail -1 | cut -d= -f2-)
    ht_clean_val "$_cg"
    printf '%s\n' "$HT_CLEAN"
}

conf_set() {
    key="$1"; val="$2"
    if grep -q "^$key=" "$CONF" 2>/dev/null; then
        sed -i "s|^$key=.*|$key=$val|" "$CONF"
    else
        echo "$key=$val" >> "$CONF"
    fi
}

feature_key() {
    case "$1" in
        boost|report-rate) echo REPORT_RATE_MODE ;;
        powerkeeper)       echo DISABLE_POWERKEEPER ;;
        powerkeeper-full)  echo POWERKEEPER_FULL_DISABLE ;;
        battery-spoof)     echo SPOOF_BATTERY_TEMP ;;
        fast-cpu)          echo FAST_CPU_RESPONSE ;;
        gpu-floor)         echo GPU_FLOOR ;;
        parallel-anim)     echo PARALLEL_ANIM ;;
        launcher-anim)     echo LAUNCHER_ANIM_RATE ;;
        force-120hz)       echo FORCE_120HZ ;;
        tg-fix)            echo TG_LAG_FIX ;;
        *)                 echo "" ;;
    esac
}

device_profile() {
    d=$(getprop ro.product.device)
    case "$d" in
        duchamp) echo "confirmed" ;;
        rodin)   echo "experimental-named" ;;
        *)       echo "experimental" ;;
    esac
}

cmd_status() {
    DEVICE=$(getprop ro.product.device)
    PROFILE=$(device_profile)
    echo "HyperTouch status"
    echo "  device         : $DEVICE ($PROFILE profile)"
    echo "  report rate    : $(conf_get REPORT_RATE_MODE)  (0=stock 1=boosted)"
    echo "  powerkeeper    : $(conf_get DISABLE_POWERKEEPER)  (1=disabled/bypassed)"
    echo "  powerkeeper full: $(conf_get POWERKEEPER_FULL_DISABLE)  (unlocks 60Hz-capped apps)"
    echo "  battery spoof  : $(conf_get SPOOF_BATTERY_TEMP)  (0=off, real temp reported)"
    echo "  fast cpu resp. : $(conf_get FAST_CPU_RESPONSE)"
    echo "  gpu floor      : $(conf_get GPU_FLOOR)"
    echo "  parallel anim  : $(conf_get PARALLEL_ANIM)  (deviceLevelList)"
    echo "  launcher anim  : $(conf_get LAUNCHER_ANIM_RATE)"
    echo "  force 120Hz    : $(conf_get FORCE_120HZ)"
    echo "  priority apps  : $(conf_get PRIORITY_APPS)"
    echo "  vm tweaks      : $(conf_get VM_TWEAKS_ENABLED)"
    echo "  tg lag fix     : $(conf_get TG_LAG_FIX)  (experimental)"
}

cmd_enable() {
    key=$(feature_key "$1")
    if [ -z "$key" ]; then
        echo "unknown feature '$1'. try: boost, powerkeeper, battery-spoof, fast-cpu, gpu-floor, powerkeeper-full, parallel-anim, launcher-anim, force-120hz, tg-fix"
        exit 1
    fi
    # Config write and the apply run it triggers share one lock hold,
    # so a concurrent apply.sh run (WebUI, boot, another CLI call)
    # can't read settings.conf mid-write, and two config writers can't
    # interleave.
    ht_lock_acquire || exit 1
    conf_set "$key" 1
    echo "enabled: $1"
    HT_LOCK_HELD=1 sh "$MODDIR/apply.sh"
    ht_lock_release
}

cmd_disable() {
    key=$(feature_key "$1")
    if [ -z "$key" ]; then
        echo "unknown feature '$1'. try: boost, powerkeeper, battery-spoof, fast-cpu, gpu-floor, powerkeeper-full, parallel-anim, launcher-anim, force-120hz, tg-fix"
        exit 1
    fi
    ht_lock_acquire || exit 1
    conf_set "$key" 0
    echo "disabled: $1"
    HT_LOCK_HELD=1 sh "$MODDIR/apply.sh"
    ht_lock_release
}

cmd_reset() {
    if [ -f "$DEFAULT_CONF" ]; then
        ht_lock_acquire || exit 1
        cp "$DEFAULT_CONF" "$CONF"
        echo "settings.conf restored to shipped defaults."
        HT_LOCK_HELD=1 sh "$MODDIR/apply.sh"
        ht_lock_release
    else
        echo "settings.conf.default not found — can't reset. Reinstall the module to restore it."
        exit 1
    fi
}

cmd_revert() {
    echo "Reverting to stock behavior for this session (settings.conf is NOT changed)..."
    ht_lock_acquire || exit 1

    # PowerKeeper: put back whatever state it was in BEFORE HyperTouch
    # (package and component are handled separately; if the user had it
    # disabled themselves, it stays disabled).
    ht_pk_restore_pkg
    ht_pk_restore_comp
    echo "  powerkeeper restored"

    # Settings-provider keys: restore exactly what was saved (including
    # "was unset" -> deleted). Animation scales are no longer touched by
    # HyperTouch at all, so they are not reset here.
    ht_restore_setting system deviceLevelList settings_deviceLevelList && echo "  restored: deviceLevelList"
    if ht_restore_setting system miui_home_animation_rate settings_miui_home_animation_rate; then
        echo "  restored: miui_home_animation_rate"
        am force-stop com.miui.home 2>/dev/null
    fi
    ht_restore_setting system min_refresh_rate settings_min_refresh_rate && echo "  restored: min_refresh_rate"
    ht_restore_setting system peak_refresh_rate settings_peak_refresh_rate && echo "  restored: peak_refresh_rate"

    # Kernel nodes: each from its saved pre-apply value. The real path is
    # read from the .node sidecar — it can NOT be rebuilt from the file
    # name (names containing "_" were mangled by the old tr '_' '/').
    ht_restore_all_nodes
    ht_restore_report_rate

    # Priority apps: whitelist + AppOps + standby bucket, for every app
    # HyperTouch actually changed, plus whatever the config currently lists.
    ht_prio_restore_all
    apps="$(conf_get PRIORITY_APPS)"
    [ "$(conf_get TG_LAG_FIX)" = "1" ] && apps="$apps org.telegram.messenger"
    set -f
    for pkg in $apps; do
        ht_valid_pkg "$pkg" && ht_prio_restore "$pkg" >/dev/null
    done
    set +f

    ht_lock_release
    echo "Reverted. Run 'action.sh' again (or tap Apply/Action) to reapply your saved settings."
}

cmd_help() {
    cat << 'EOF'
HyperTouch management CLI

  action.sh                    re-apply current settings
  action.sh status              show current settings + device profile
  action.sh enable <feature>    boost | powerkeeper | battery-spoof |
                                fast-cpu | gpu-floor | powerkeeper-full |
                                parallel-anim | launcher-anim | force-120hz |
                                tg-fix
  action.sh disable <feature>   (same feature names)
  action.sh reset               restore settings.conf to shipped defaults
  action.sh revert              temporarily undo tweaks (settings kept)
  action.sh help                 this text
EOF
}

case "$1" in
    "")            sh "$MODDIR/apply.sh" ;;
    status)        cmd_status ;;
    enable)        cmd_enable "$2" ;;
    disable)       cmd_disable "$2" ;;
    reset)         cmd_reset ;;
    revert)        cmd_revert ;;
    help|--help|-h) cmd_help ;;
    *)             echo "unknown command '$1'"; cmd_help; exit 1 ;;
esac
