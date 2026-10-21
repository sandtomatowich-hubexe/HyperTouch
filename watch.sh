#!/system/bin/sh
# HyperTouch keep-applied watcher.
#
# Xiaomi's services (touch HAL, thermal engine, power HAL) rewrite some of
# these kernel values after screen off/on, game launches and charging
# changes, and HyperTouch otherwise only applies at boot and on Apply. This
# loop checks every INTERVAL seconds, with shell builtins only (no process
# spawned, no battery to speak of), whether the touch report rate and the
# CPU rate limit still hold the values HyperTouch set. Only when one has
# changed does it run apply.sh in its light "quick" mode, which re-writes
# just those two values.
#
# Deliberately NOT re-asserted: the thermal profile, governors, GPU floor,
# and everything in the Settings provider — fighting Xiaomi's thermal engine
# or Game Turbo for those would cause the very conflicts we want to avoid.
#
# Started by apply.sh, stopped by `action.sh revert` / uninstall, and it
# exits by itself if the module is disabled or removed or KEEP_APPLIED=0.

MODDIR=${0%/*}
INTERVAL=${HT_WATCH_INTERVAL:-30}
LOGTAG="HyperTouch"

# shellcheck disable=SC1090
. "$MODDIR/common.sh"

# One watcher at a time.
_old=$(cat "$MODDIR/.watch.pid" 2>/dev/null)
if [ -n "$_old" ] && [ "$_old" != "$$" ] && kill -0 "$_old" 2>/dev/null; then
    exit 0
fi
echo $$ > "$MODDIR/.watch.pid"
trap 'rm -f "$MODDIR/.watch.pid" 2>/dev/null' EXIT
trap 'exit 0' INT TERM

# Pure-builtin read of a node's first line into $_v.
rd() { _v=""; [ -r "$1" ] && read -r _v < "$1" 2>/dev/null; }

# 0 = all watched values are as configured, 1 = something drifted.
drifted() {
    for _n in /sys/devices/platform/goodix_ts.0/goodix_ts_report_rate /sys/devices/platform/goodix_ts.0/switch_report_rate; do
        if [ -r "$_n" ]; then
            rd "$_n"
            case "$REPORT_RATE_MODE" in
                1) case "$_v" in *480[Hh][Zz]*) ;; *) return 0 ;; esac ;;
                *) case "$_v" in *240[Hh][Zz]*) ;; *) return 0 ;; esac ;;
            esac
        fi
    done
    if [ "$FAST_CPU_RESPONSE" = "1" ]; then
        for _p in /sys/devices/system/cpu/cpufreq/policy*/schedutil; do
            for _f in rate_limit_us up_rate_limit_us; do
                if [ -r "$_p/$_f" ]; then
                    rd "$_p/$_f"
                    [ "$_v" = "500" ] || return 0
                fi
            done
        done
    fi
    return 1
}

skip=0
while :; do
    sleep "$INTERVAL"
    [ -d "$MODDIR" ] || exit 0
    [ -f "$MODDIR/disable" ] || [ -f "$MODDIR/remove" ] && exit 0

    if [ "$skip" -gt 0 ]; then skip=$((skip - 1)); continue; fi

    REPORT_RATE_MODE=1; FAST_CPU_RESPONSE=1; KEEP_APPLIED=1
    ht_load_conf "$MODDIR/settings.conf"
    [ "$KEEP_APPLIED" = "1" ] || exit 0

    if drifted; then
        HT_QUICK=1 HT_LOCK_WAIT=5 sh "$MODDIR/apply.sh" >/dev/null 2>&1
        rc=$?
        # 3 = this device has no hardware profile, nothing to keep applied.
        [ "$rc" = "3" ] && exit 0
        # Still drifted right after re-applying (e.g. a node that reads back
        # in a format we don't recognise): back off instead of retrying
        # every cycle.
        drifted && skip=10
    fi
done
