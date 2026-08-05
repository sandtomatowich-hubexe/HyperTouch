#!/system/bin/sh
# HyperTouch — applies the tweaks from settings.conf.
# Called by service.sh at boot, by action.sh from the manager's Action
# button, and by the WebUI's "Apply now" button. Safe to run repeatedly.

MODDIR=${0%/*}
CONF="$MODDIR/settings.conf"
LOGTAG="HyperTouch"

write() {
    # Only writes if the node exists and is writable; silently skips
    # otherwise so an unrecognized path never breaks the script.
    if [ -w "$1" ]; then
        echo "$2" > "$1" 2>/dev/null
        log -p i -t "$LOGTAG" "applied $1 = $2"
        return 0
    fi
    log -p w -t "$LOGTAG" "skipped (not writable): $1"
    return 1
}

# ---- defaults, overridden by settings.conf ----
REPORT_RATE_MODE=1
DISABLE_POWERKEEPER=1
SPOOF_BATTERY_TEMP=0
TOUCH_SENSITIVITY_PATH=
TOUCH_SENSITIVITY_VALUE=
TOUCH_EDGE_PATH=
TOUCH_EDGE_VALUE=
PALM_REJECT_PATH=
PALM_REJECT_VALUE=

# shellcheck disable=SC1090
[ -f "$CONF" ] && . "$CONF"

# ---- PowerKeeper (MIUI/HyperOS background throttling) ----
if [ "$DISABLE_POWERKEEPER" = "1" ]; then
    pm disable-user --user 0 com.miui.powerkeeper/.statemachine.PowerStateMachineService >/dev/null 2>&1
fi

# ---- Touch: sampling / report rate boost ----
write /sys/devices/platform/goodix_ts.0/switch_report_rate "$REPORT_RATE_MODE"

# ---- Touch: sensitivity / edge (glove) / palm rejection ----
# These paths aren't confirmed for this kernel build yet. Run
# tools/probe_touch.sh as root and fill them into settings.conf once
# you know the real node names — this script will pick them up as-is.
[ -n "$TOUCH_SENSITIVITY_PATH" ] && [ -n "$TOUCH_SENSITIVITY_VALUE" ] && \
    write "$TOUCH_SENSITIVITY_PATH" "$TOUCH_SENSITIVITY_VALUE"
[ -n "$TOUCH_EDGE_PATH" ] && [ -n "$TOUCH_EDGE_VALUE" ] && \
    write "$TOUCH_EDGE_PATH" "$TOUCH_EDGE_VALUE"
[ -n "$PALM_REJECT_PATH" ] && [ -n "$PALM_REJECT_VALUE" ] && \
    write "$PALM_REJECT_PATH" "$PALM_REJECT_VALUE"

# ---- GPU / CPU governors ----
write /sys/devices/platform/soc/13000000.mali/devfreq/13000000.mali/governor "simple_ondemand"
write /sys/devices/system/cpu/cpufreq/policy0/scaling_governor "schedutil"
write /sys/devices/system/cpu/cpufreq/policy4/scaling_governor "schedutil"
write /sys/devices/system/cpu/cpufreq/policy7/scaling_governor "schedutil"
write /sys/devices/virtual/thermal/thermal_message/sconfig 6

# ---- Battery temp spoof (off by default — see README) ----
if [ "$SPOOF_BATTERY_TEMP" = "1" ]; then
    write /sys/class/power_supply/bms/temp 250
fi

log -p i -t "$LOGTAG" "apply.sh completed."
