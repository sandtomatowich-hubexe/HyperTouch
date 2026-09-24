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
#                                 parallel-anim | launcher-anim | tg-fix
#   action.sh disable <feature>   (same feature names)
#   action.sh reset               restore settings.conf to shipped defaults
#   action.sh revert              temporarily undo tweaks (settings.conf kept)
#   action.sh help                show this text

MODDIR=${0%/*}
CONF="$MODDIR/settings.conf"
DEFAULT_CONF="$MODDIR/settings.conf.default"

# shellcheck disable=SC1090
. "$MODDIR/lock.sh"

conf_get() { grep "^$1=" "$CONF" 2>/dev/null | tail -1 | cut -d= -f2-; }

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
    echo "  smooth touch   : $(conf_get SMOOTH_TOUCH_MODE)  (0=stock 1=fast 2=instant)"
    echo "  parallel anim  : $(conf_get PARALLEL_ANIM)  (deviceLevelList)"
    echo "  launcher anim  : $(conf_get LAUNCHER_ANIM_RATE)"
    echo "  priority apps  : $(conf_get PRIORITY_APPS)"
    echo "  tg lag fix     : $(conf_get TG_LAG_FIX)  (experimental)"
}

cmd_enable() {
    key=$(feature_key "$1")
    if [ -z "$key" ]; then
        echo "unknown feature '$1'. try: boost, powerkeeper, battery-spoof, fast-cpu, gpu-floor, powerkeeper-full, parallel-anim, launcher-anim, tg-fix"
        exit 1
    fi
    # Config write and the apply run it triggers share one lock hold,
    # so a concurrent apply.sh run (WebUI, boot, another CLI call)
    # can't read settings.conf mid-write, and two config writers can't
    # interleave.
    ht_lock_acquire
    conf_set "$key" 1
    echo "enabled: $1"
    HT_LOCK_HELD=1 sh "$MODDIR/apply.sh"
    ht_lock_release
}

cmd_disable() {
    key=$(feature_key "$1")
    if [ -z "$key" ]; then
        echo "unknown feature '$1'. try: boost, powerkeeper, battery-spoof, fast-cpu, gpu-floor, powerkeeper-full, parallel-anim, launcher-anim, tg-fix"
        exit 1
    fi
    ht_lock_acquire
    conf_set "$key" 0
    echo "disabled: $1"
    HT_LOCK_HELD=1 sh "$MODDIR/apply.sh"
    ht_lock_release
}

cmd_reset() {
    if [ -f "$DEFAULT_CONF" ]; then
        ht_lock_acquire
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
    ht_lock_acquire

    STATE_DIR="$MODDIR/.state"

    # PowerKeeper: undo whichever level apply_powerkeeper actually
    # applied. Full-disable (pm disable-user on the whole package)
    # needs the whole package re-enabled — re-enabling just the
    # statemachine component, as before, leaves the package itself
    # disabled and PowerKeeper never comes back.
    if pm path com.miui.powerkeeper >/dev/null 2>&1 || pm list packages -d 2>/dev/null | grep -q com.miui.powerkeeper; then
        pm enable com.miui.powerkeeper >/dev/null 2>&1
        pm enable com.miui.powerkeeper/.statemachine.PowerStateMachineService >/dev/null 2>&1
    fi

    # Android Settings.System / Settings.Global keys apply.sh touches.
    # These have no single "stock" value across devices/OEMs, so
    # restore from what was actually there before, when we saved it;
    # animation scales are the one exception with a real universal
    # default (1.0 = OS default, unset).
    settings put global window_animation_scale 1.0 2>/dev/null
    settings put global transition_animation_scale 1.0 2>/dev/null
    settings put global animator_duration_scale 1.0 2>/dev/null

    if [ "$(conf_get PARALLEL_ANIM)" = "1" ] && [ -f "$STATE_DIR/settings_deviceLevelList" ]; then
        settings put system deviceLevelList "$(cat "$STATE_DIR/settings_deviceLevelList")" 2>/dev/null
    fi
    if [ "$(conf_get LAUNCHER_ANIM_RATE)" = "1" ] && [ -f "$STATE_DIR/settings_miui_home_animation_rate" ]; then
        settings put system miui_home_animation_rate "$(cat "$STATE_DIR/settings_miui_home_animation_rate")" 2>/dev/null
    fi

    # Kernel sysfs nodes: restore each from its saved pre-apply value
    # if we have one, rather than guessing a stock number (governor
    # names, rate limits, and thermal levels vary by kernel build —
    # there's no single "correct" value to hardcode here).
    if [ -d "$STATE_DIR" ]; then
        for f in "$STATE_DIR"/_sys_*; do
            [ -f "$f" ] || continue
            node=$(basename "$f" | tr '_' '/')
            node="/${node#/}"
            if [ -w "$node" ]; then
                cat "$f" > "$node" 2>/dev/null
            fi
        done
    fi

    if [ -w /sys/devices/platform/goodix_ts.0/switch_report_rate ]; then
        echo 0 > /sys/devices/platform/goodix_ts.0/switch_report_rate 2>/dev/null
    fi

    apps="$(conf_get PRIORITY_APPS)"
    [ "$(conf_get TG_LAG_FIX)" = "1" ] && apps="$apps org.telegram.messenger"
    for pkg in $apps; do
        [ -z "$pkg" ] && continue
        dumpsys deviceidle whitelist "-$pkg" >/dev/null 2>&1
        cmd appops set "$pkg" RUN_IN_BACKGROUND default >/dev/null 2>&1
        cmd appops set "$pkg" RUN_ANY_IN_BACKGROUND default >/dev/null 2>&1
    done

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
                                parallel-anim | launcher-anim | tg-fix
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
