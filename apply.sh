#!/system/bin/sh
# HyperTouch — applies tweaks from settings.conf.
# Called by service.sh (boot), action.sh (manager Action button / CLI),
# and the WebUI ("Apply now"). Safe to run repeatedly.

MODDIR=${0%/*}
CONF="$MODDIR/settings.conf"
LOGTAG="HyperTouch"

write() {
    # Only writes if the node exists and is writable; silently skips
    # otherwise so an unrecognized/wrong-device path never breaks the
    # script — it just gets logged and moved past.
    if [ -w "$1" ]; then
        echo "$2" > "$1" 2>/dev/null
        log -p i -t "$LOGTAG" "applied $1 = $2"
        return 0
    fi
    log -p w -t "$LOGTAG" "skipped (not writable): $1"
    return 1
}

# ── defaults, overridden by settings.conf ──────────────────
REPORT_RATE_MODE=1
DISABLE_POWERKEEPER=1
SPOOF_BATTERY_TEMP=0
TOUCH_SENSITIVITY_PATH=
TOUCH_SENSITIVITY_VALUE=
TOUCH_EDGE_PATH=
TOUCH_EDGE_VALUE=
PALM_REJECT_PATH=
PALM_REJECT_VALUE=
SMOOTH_TOUCH_MODE=1
PRIORITY_APPS=
TG_LAG_FIX=0
UI_STYLE=material

# shellcheck disable=SC1090
[ -f "$CONF" ] && . "$CONF"

# ── Device profile ──────────────────────────────────────────
# Hardware-specific sysfs paths (governors, thermal, touch report
# rate) only get applied on devices we've actually confirmed against
# real hardware. Everything else runs in "experimental" mode: kernel-
# independent features (Smooth Touch, Priority Apps, PowerKeeper) still
# work, but hardware paths are skipped rather than guessed. Set
# FORCE_EXPERIMENTAL=1 in settings.conf to try them anyway — they're
# guarded by write()'s -w check either way, so a wrong guess just no-ops.
DEVICE=$(getprop ro.product.device)

case "$DEVICE" in
    duchamp)
        DEVICE_PROFILE="confirmed"
        GOODIX_PATH="/sys/devices/platform/goodix_ts.0/switch_report_rate"
        MALI_GOV_PATH="/sys/devices/platform/soc/13000000.mali/devfreq/13000000.mali/governor"
        CPU_POLICIES="0 4 7"
        THERMAL_SCONFIG_PATH="/sys/devices/virtual/thermal/thermal_message/sconfig"
        BMS_TEMP_PATH="/sys/class/power_supply/bms/temp"
        ;;
    *)
        DEVICE_PROFILE="experimental"
        GOODIX_PATH="/sys/devices/platform/goodix_ts.0/switch_report_rate"
        MALI_GOV_PATH="/sys/devices/platform/soc/13000000.mali/devfreq/13000000.mali/governor"
        CPU_POLICIES="0 4 7"
        THERMAL_SCONFIG_PATH="/sys/devices/virtual/thermal/thermal_message/sconfig"
        BMS_TEMP_PATH="/sys/class/power_supply/bms/temp"
        ;;
esac

log -p i -t "$LOGTAG" "device=$DEVICE profile=$DEVICE_PROFILE"

apply_hardware_tweaks() {
    write "$GOODIX_PATH" "$REPORT_RATE_MODE"

    [ -n "$TOUCH_SENSITIVITY_PATH" ] && [ -n "$TOUCH_SENSITIVITY_VALUE" ] && \
        write "$TOUCH_SENSITIVITY_PATH" "$TOUCH_SENSITIVITY_VALUE"
    [ -n "$TOUCH_EDGE_PATH" ] && [ -n "$TOUCH_EDGE_VALUE" ] && \
        write "$TOUCH_EDGE_PATH" "$TOUCH_EDGE_VALUE"
    [ -n "$PALM_REJECT_PATH" ] && [ -n "$PALM_REJECT_VALUE" ] && \
        write "$PALM_REJECT_PATH" "$PALM_REJECT_VALUE"

    write "$MALI_GOV_PATH" "simple_ondemand"
    for p in $CPU_POLICIES; do
        write "/sys/devices/system/cpu/cpufreq/policy$p/scaling_governor" "schedutil"
    done
    write "$THERMAL_SCONFIG_PATH" 6

    if [ "$SPOOF_BATTERY_TEMP" = "1" ]; then
        write "$BMS_TEMP_PATH" 250
    fi
}

# ── PowerKeeper (MIUI/HyperOS only, safely no-ops on AOSP) ──
apply_powerkeeper() {
    if ! pm path com.miui.powerkeeper >/dev/null 2>&1; then
        log -p i -t "$LOGTAG" "powerkeeper: package not present, skipping"
        return
    fi
    if [ "$DISABLE_POWERKEEPER" = "1" ]; then
        pm disable-user --user 0 com.miui.powerkeeper/.statemachine.PowerStateMachineService >/dev/null 2>&1
        log -p i -t "$LOGTAG" "powerkeeper: disabled"
    else
        pm enable com.miui.powerkeeper/.statemachine.PowerStateMachineService >/dev/null 2>&1
        log -p i -t "$LOGTAG" "powerkeeper: enabled (stock)"
    fi
}

# ── Smooth Touch — userspace animation scaling, kernel-independent ──
apply_smooth_touch() {
    case "$SMOOTH_TOUCH_MODE" in
        0) scale="1.0" ;;
        2) scale="0.0" ;;
        *) scale="0.5" ;;
    esac
    settings put global window_animation_scale "$scale" 2>/dev/null
    settings put global transition_animation_scale "$scale" 2>/dev/null
    settings put global animator_duration_scale "$scale" 2>/dev/null
    log -p i -t "$LOGTAG" "smooth touch: animation scale=$scale"
}

# ── Priority Apps — background-restriction exemption, kernel-independent ──
# Not a rendering-level fix; exempts listed packages from Doze / App
# Standby / PowerKeeper so background throttling can't contribute to
# jank when they're reopened. TG_LAG_FIX is a convenience preset for
# this, not a separate mechanism.
apply_priority_apps() {
    apps="$PRIORITY_APPS"
    [ "$TG_LAG_FIX" = "1" ] && apps="$apps org.telegram.messenger"
    for pkg in $apps; do
        [ -z "$pkg" ] && continue
        if ! pm path "$pkg" >/dev/null 2>&1; then
            log -p w -t "$LOGTAG" "priority app not installed, skipping: $pkg"
            continue
        fi
        dumpsys deviceidle whitelist "+$pkg" >/dev/null 2>&1
        cmd appops set "$pkg" RUN_IN_BACKGROUND allow >/dev/null 2>&1
        cmd appops set "$pkg" RUN_ANY_IN_BACKGROUND allow >/dev/null 2>&1
        am set-standby-bucket "$pkg" active >/dev/null 2>&1
        log -p i -t "$LOGTAG" "priority app exempted: $pkg"
    done
}

# ── run ──
if [ "$DEVICE_PROFILE" = "confirmed" ] || [ "$FORCE_EXPERIMENTAL" = "1" ]; then
    apply_hardware_tweaks
else
    log -p w -t "$LOGTAG" "device '$DEVICE' has no confirmed profile — hardware tweaks skipped. Set FORCE_EXPERIMENTAL=1 to try duchamp's paths anyway."
fi

apply_powerkeeper
apply_smooth_touch
apply_priority_apps

log -p i -t "$LOGTAG" "apply.sh completed (profile=$DEVICE_PROFILE)."
