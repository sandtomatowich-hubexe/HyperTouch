#!/system/bin/sh
# HyperTouch — applies tweaks from settings.conf.
# Called by service.sh (boot), action.sh (manager Action button / CLI),
# and the WebUI ("Apply now"). Safe to run repeatedly.
#
# Every step echoes to stdout *and* logs to logcat — the logcat side is
# for later debugging, the echo side is what the manager's Action
# console actually displays live.

MODDIR=${0%/*}
CONF="$MODDIR/settings.conf"
LOGTAG="HyperTouch"

say() {
    echo "$1"
    log -p i -t "$LOGTAG" "$1"
}
warn() {
    echo "! $1"
    log -p w -t "$LOGTAG" "$1"
}

write() {
    # Only writes if the node exists and is writable; silently skips
    # otherwise so an unrecognized/wrong-device path never breaks the
    # script — it just gets reported and moved past.
    if [ -w "$1" ]; then
        echo "$2" > "$1" 2>/dev/null
        say "  applied: ${1##*/} = $2"
        return 0
    fi
    warn "  skipped (not writable): $1"
    return 1
}

echo "── HyperTouch: applying settings ──"

# ── Concurrency lock ─────────────────────────────────────────
# mkdir is atomic on POSIX filesystems, so this can't race. If the
# WebUI and the manager's Action button fire close together, the
# second one waits instead of reading settings.conf mid-write by the
# first — that overlap was a real, if rare, way for a just-made change
# to silently appear reverted.
LOCK="$MODDIR/.apply.lock"
i=0
while ! mkdir "$LOCK" 2>/dev/null; do
    i=$((i + 1))
    if [ "$i" -gt 8 ]; then
        # Stale lock from a crashed run — clear it rather than hang forever.
        rmdir "$LOCK" 2>/dev/null
        break
    fi
    sleep 1
done
trap 'rmdir "$LOCK" 2>/dev/null' EXIT INT TERM


# ── defaults, overridden by settings.conf ──────────────────
REPORT_RATE_MODE=1
DISABLE_POWERKEEPER=1
POWERKEEPER_FULL_DISABLE=0
SPOOF_BATTERY_TEMP=0
SMOOTH_TOUCH_MODE=1
PRIORITY_APPS=
TG_LAG_FIX=0
PARALLEL_ANIM=0
LAUNCHER_ANIM_RATE=0
FAST_CPU_RESPONSE=1
GPU_FLOOR=0

# shellcheck disable=SC1090
[ -f "$CONF" ] && . "$CONF"

# ── Device profile ──────────────────────────────────────────
# Hardware-specific sysfs paths only run on devices we've actually
# confirmed against real hardware, or devices with a named experimental
# profile built from real published specs (not guesses at a random
# device's exact register layout). Everything else runs kernel-
# independent features only. Every write is guarded by write()'s -w
# check regardless, so a wrong guess just no-ops rather than doing
# something unexpected — but "guarded" isn't the same as "confirmed".
DEVICE=$(getprop ro.product.device)

case "$DEVICE" in
    duchamp)
        # Poco X6 Pro 5G / Redmi K70E — Dimensity 8300-Ultra. Fully
        # confirmed against real hardware.
        DEVICE_PROFILE="confirmed"
        GOODIX_PATH="/sys/devices/platform/goodix_ts.0/switch_report_rate"
        MALI_PLATFORM="/sys/devices/platform/soc/13000000.mali/devfreq/13000000.mali"
        CPU_POLICIES="0 4 7"
        THERMAL_SCONFIG_PATH="/sys/devices/virtual/thermal/thermal_message/sconfig"
        BMS_TEMP_PATH="/sys/class/power_supply/bms/temp"
        ;;
    rodin)
        # POCO X7 Pro / Redmi Turbo 4 — Dimensity 8400-Ultra. Never
        # probed on real hardware. Reuses duchamp's CPU_POLICIES because
        # both chips genuinely share the same 1+3+4 cluster topology
        # (published spec, not a guess) — but the touch/GPU paths below
        # are carried over unverified, purely as a starting guess.
        DEVICE_PROFILE="experimental-named"
        GOODIX_PATH="/sys/devices/platform/goodix_ts.0/switch_report_rate"
        MALI_PLATFORM="/sys/devices/platform/soc/13000000.mali/devfreq/13000000.mali"
        CPU_POLICIES="0 4 7"
        THERMAL_SCONFIG_PATH="/sys/devices/virtual/thermal/thermal_message/sconfig"
        BMS_TEMP_PATH="/sys/class/power_supply/bms/temp"
        ;;
    *)
        DEVICE_PROFILE="experimental"
        GOODIX_PATH="/sys/devices/platform/goodix_ts.0/switch_report_rate"
        MALI_PLATFORM="/sys/devices/platform/soc/13000000.mali/devfreq/13000000.mali"
        CPU_POLICIES="0 4 7"
        THERMAL_SCONFIG_PATH="/sys/devices/virtual/thermal/thermal_message/sconfig"
        BMS_TEMP_PATH="/sys/class/power_supply/bms/temp"
        ;;
esac

say "device: $DEVICE ($DEVICE_PROFILE profile)"

apply_hardware_tweaks() {
    echo "→ hardware tweaks"
    write "$GOODIX_PATH" "$REPORT_RATE_MODE"
    write "$MALI_PLATFORM/governor" "simple_ondemand"
    for p in $CPU_POLICIES; do
        write "/sys/devices/system/cpu/cpufreq/policy$p/scaling_governor" "schedutil"
    done
    write "$THERMAL_SCONFIG_PATH" 6

    if [ "$SPOOF_BATTERY_TEMP" = "1" ]; then
        write "$BMS_TEMP_PATH" 250
    fi
}

# ── Duchamp Tuning — real, working responsiveness tweaks ────
# Standard Linux/Android kernel tunables, not fabricated paths. Only
# runs on confirmed/named-experimental devices since it touches
# CPU/GPU scaling behavior specific to this chip family.
apply_duchamp_tuning() {
    echo "→ duchamp tuning"
    if [ "$FAST_CPU_RESPONSE" = "1" ]; then
        for p in $CPU_POLICIES; do
            sd="/sys/devices/system/cpu/cpufreq/policy$p/schedutil"
            write "$sd/up_rate_limit_us" 500
            write "$sd/down_rate_limit_us" 20000
        done
        say "  fast CPU response: ramps up quicker on touch input"
    fi
    if [ "$GPU_FLOOR" = "1" ]; then
        freqs="$MALI_PLATFORM/available_frequencies"
        floor_file="$MALI_PLATFORM/min_freq"
        if [ -r "$freqs" ] && [ -w "$floor_file" ]; then
            floor=$(tr ' ' '\n' < "$freqs" | sort -n | sed -n '2p')
            if [ -n "$floor" ]; then
                write "$floor_file" "$floor"
            else
                warn "  GPU floor: couldn't parse available_frequencies"
            fi
        else
            warn "  GPU floor: available_frequencies not readable, skipping"
        fi
    fi
}

# ── PowerKeeper (MIUI/HyperOS only, safely no-ops on AOSP) ──
apply_powerkeeper() {
    echo "→ powerkeeper"
    if ! pm path com.miui.powerkeeper >/dev/null 2>&1; then
        say "  not present on this ROM, skipping"
        return
    fi
    if [ "$DISABLE_POWERKEEPER" = "1" ]; then
        pm disable-user --user 0 com.miui.powerkeeper/.statemachine.PowerStateMachineService >/dev/null 2>&1
        say "  disabled"
    else
        pm enable com.miui.powerkeeper/.statemachine.PowerStateMachineService >/dev/null 2>&1
        say "  enabled (stock)"
    fi

    # Community-verified separately from the single-component disable
    # above: PowerKeeper (branded "Battery & Performance") is also
    # what caps some apps to 60Hz even on 120Hz-capable phones.
    # Disabling the whole app — not just the state-machine service —
    # is the confirmed fix, but it's a bigger behavior change (loses
    # the "Battery Saver" entry in per-app battery settings), so it's
    # its own opt-in toggle rather than silently folded into the one
    # above.
    if [ "$POWERKEEPER_FULL_DISABLE" = "1" ]; then
        pm disable-user --user 0 com.miui.powerkeeper >/dev/null 2>&1
        say "  fully disabled (unlocks apps HyperOS caps to 60Hz)"
    fi
}

# ── Smooth Touch — userspace animation scaling, kernel-independent ──
apply_smooth_touch() {
    echo "→ smooth touch"
    case "$SMOOTH_TOUCH_MODE" in
        0) scale="1.0" ;;
        2) scale="0.0" ;;
        *) scale="0.5" ;;
    esac
    settings put global window_animation_scale "$scale" 2>/dev/null
    settings put global transition_animation_scale "$scale" 2>/dev/null
    settings put global animator_duration_scale "$scale" 2>/dev/null
    say "  animation scale = $scale"
}

# ── Parallel Animation — real mechanism, confirmed working ──
# Not a made-up prop this time: deviceLevelList is a genuine
# Settings.System key HyperOS reads to decide which animation tier a
# device gets. duchamp/rodin are hardware-capable but classified below
# the tier that unlocks it — this raises the classification directly,
# no launcher/app modification involved.
apply_parallel_anim() {
    [ "$PARALLEL_ANIM" != "1" ] && return
    echo "→ parallel animation"
    settings put system deviceLevelList "v:1,c:3,g:3" 2>/dev/null
    say "  deviceLevelList set to v:1,c:3,g:3 (reboot recommended)"
}

# ── Launcher animation rate — com.miui.home, no launcher edits ──
# Same idea as above but scoped specifically to the launcher: this is
# a Settings.System key the stock launcher itself reads at runtime, so
# it's a real way to influence com.miui.home's animation behavior
# without touching the launcher's own code (no Java/smali involved).
apply_launcher_anim() {
    [ "$LAUNCHER_ANIM_RATE" != "1" ] && return
    echo "→ launcher animation rate"
    settings put system miui_home_animation_rate 1 2>/dev/null
    say "  miui_home_animation_rate set to 1 (force-stop the launcher, or reboot, to see it)"
}

# ── Priority Apps — background-restriction exemption, kernel-independent ──
apply_priority_apps() {
    apps="$PRIORITY_APPS"
    [ "$TG_LAG_FIX" = "1" ] && apps="$apps org.telegram.messenger"
    apps="$(echo "$apps" | xargs)"
    if [ -z "$apps" ]; then
        return
    fi
    echo "→ priority apps"
    for pkg in $apps; do
        [ -z "$pkg" ] && continue
        if ! pm path "$pkg" >/dev/null 2>&1; then
            warn "  not installed, skipping: $pkg"
            continue
        fi
        dumpsys deviceidle whitelist "+$pkg" >/dev/null 2>&1
        cmd appops set "$pkg" RUN_IN_BACKGROUND allow >/dev/null 2>&1
        cmd appops set "$pkg" RUN_ANY_IN_BACKGROUND allow >/dev/null 2>&1
        am set-standby-bucket "$pkg" active >/dev/null 2>&1
        say "  exempted: $pkg"
    done
}

# ── Live device info → module.prop description ──────────────
# module.prop is normally static, but its description field is
# re-read by the manager UI each time the module list refreshes, so
# rewriting it here gives a genuinely live status line instead of a
# fixed string — current touch mode, kernel, refresh rate, right in
# the manager's module list, no need to open the WebUI to check.
update_live_info() {
    PROP="$MODDIR/module.prop"
    [ -w "$PROP" ] || return

    kernel=$(uname -r 2>/dev/null | cut -d- -f1)
    rate_status="stock"
    [ "$REPORT_RATE_MODE" = "1" ] && rate_status="boosted"

    # dumpsys display lists every supported mode's fps, not just the
    # active one — grabbing the first match was the 60-vs-120 bug.
    # Taking the highest value found is a better heuristic: the WebUI
    # is actively being interacted with when this runs, so the display
    # is very likely at (or near) its max rate at that moment.
    refresh=$(dumpsys display 2>/dev/null | grep -o 'fps=[0-9]*\.[0-9]*' | cut -d= -f2 | sort -rn | head -1)
    [ -z "$refresh" ] && refresh="?"

    mem_total_kb=$(awk '/MemTotal/{print $2}' /proc/meminfo 2>/dev/null)
    mem_avail_kb=$(awk '/MemAvailable/{print $2}' /proc/meminfo 2>/dev/null)
    if [ -n "$mem_total_kb" ] && [ -n "$mem_avail_kb" ]; then
        mem_used_gb=$(awk "BEGIN{printf \"%.1f\", ($mem_total_kb-$mem_avail_kb)/1048576}")
        mem_total_gb=$(awk "BEGIN{printf \"%.1f\", $mem_total_kb/1048576}")
        ram="${mem_used_gb}/${mem_total_gb}GB"
    else
        ram="?"
    fi

    desc="Touch: $rate_status · ${refresh}Hz · RAM $ram · kernel $kernel · $DEVICE_PROFILE"
    sed -i "s|^description=.*|description=$desc|" "$PROP" 2>/dev/null
}

# TG_LAG_FIX bundles the verified PowerKeeper full-disable, since
# that's what's actually confirmed to unlock apps HyperOS caps to
# 60Hz — not MIUI Optimization, which was tested and didn't help.
# Priority Apps (background exemption) stays layered on too. Telegram
# also has its own animated-background rendering that HyperTouch has
# no way to reach from outside the app — see README for that manual
# step, since a root tweak fundamentally can't touch it.
if [ "$TG_LAG_FIX" = "1" ]; then
    POWERKEEPER_FULL_DISABLE=1
fi

# ── run ──
if [ "$DEVICE_PROFILE" = "confirmed" ] || [ "$DEVICE_PROFILE" = "experimental-named" ] || [ "$FORCE_EXPERIMENTAL" = "1" ]; then
    apply_hardware_tweaks
    apply_duchamp_tuning
else
    warn "device '$DEVICE' has no confirmed or named-experimental profile — hardware tweaks skipped (set FORCE_EXPERIMENTAL=1 to try duchamp's paths anyway)"
fi

apply_powerkeeper
apply_smooth_touch
apply_parallel_anim
apply_launcher_anim
apply_priority_apps
update_live_info

echo "── done ──"
log -p i -t "$LOGTAG" "apply.sh completed (profile=$DEVICE_PROFILE)."
