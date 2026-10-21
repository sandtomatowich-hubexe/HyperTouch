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
    #
    # -w passing doesn't guarantee the write itself succeeds (kernel
    # can reject the value, node can be write-once, etc.), so the
    # actual `echo >` exit status is what decides success/failure —
    # not just node existence.
    if [ ! -w "$1" ]; then
        warn "  skipped (not writable): $1"
        return 1
    fi
    if echo "$2" > "$1" 2>/dev/null; then
        say "  applied: ${1##*/} = $2"
        return 0
    fi
    warn "  failed to write: ${1##*/} = $2"
    return 1
}

# Shared helpers (safe config loader, original-value state, restore).
# shellcheck disable=SC1090
. "$MODDIR/common.sh"
APPLY_RC=0

echo "── HyperTouch: applying settings ──"

# ── Concurrency lock ─────────────────────────────────────────
# Shared with action.sh (see lock.sh). HT_LOCK_HELD=1 means the caller
# (action.sh enable/disable/reset) already holds it and is waiting on us,
# so re-acquiring would deadlock.
# shellcheck disable=SC1090
. "$MODDIR/lock.sh"
if [ "$HT_LOCK_HELD" != "1" ]; then
    ht_lock_acquire || { warn "could not get the HyperTouch lock — nothing applied"; exit 1; }
fi

# ── defaults, overridden by settings.conf ──────────────────
REPORT_RATE_MODE=1
DISABLE_POWERKEEPER=1
POWERKEEPER_FULL_DISABLE=0
SPOOF_BATTERY_TEMP=0
PRIORITY_APPS=
TG_LAG_FIX=0
PARALLEL_ANIM=0
LAUNCHER_ANIM_RATE=0
FORCE_120HZ=0
FAST_CPU_RESPONSE=1
GPU_FLOOR=0
VM_TWEAKS_ENABLED=0
SWAPPINESS=60
FORCE_EXPERIMENTAL=0

# settings.conf is parsed, never executed (see common.sh).
ht_load_conf "$CONF"

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
        CPU_GOV_FORCE=1    # switch CPU clusters to schedutil (original duchamp behaviour)
        GPU_GOV_FORCE=1    # switch Mali devfreq governor to simple_ondemand
        ;;
    rodin)
        # POCO X7 Pro / Redmi Turbo 4 — Dimensity 8400-Ultra (MT6899).
        # Probed on real units: the Goodix node, Mali devfreq path, thermal
        # sconfig, bms temp and 0/4/7 cluster layout match duchamp, and
        # writing 0 / 1 to switch_report_rate reads back 240HZ / 480HZ.
        # BUT readback only proves the node accepted the value. A tester
        # reported no real 480Hz effect, and the Rodin Essential project's
        # docs state its 240/480Hz control goes through Xiaomi's touch HAL
        # (the goodix_ts.0 sysfs node is only a fallback when that service
        # is missing). So touch boost on Rodin is UNVERIFIED and this stays
        # "experimental-named" until a measured effect is shown.
        #
        # Governors are NOT forced here (probe findings):
        #  * the Mali governor is "dummy" (MediaTek's own GPU DVFS is in
        #    charge); forcing devfreq's simple_ondemand would take that over
        #  * some units run a custom kernel whose CPU governor is
        #    "sugov_ext" (no schedutil dir), so forcing schedutil would
        #    replace the vendor-tuned governor
        DEVICE_PROFILE="experimental-named"
        GOODIX_PATH="/sys/devices/platform/goodix_ts.0/switch_report_rate"
        MALI_PLATFORM="/sys/devices/platform/soc/13000000.mali/devfreq/13000000.mali"
        CPU_POLICIES="0 4 7"
        THERMAL_SCONFIG_PATH="/sys/devices/virtual/thermal/thermal_message/sconfig"
        BMS_TEMP_PATH="/sys/class/power_supply/bms/temp"
        CPU_GOV_FORCE=0
        GPU_GOV_FORCE=0
        ;;
    *)
        DEVICE_PROFILE="experimental"
        GOODIX_PATH="/sys/devices/platform/goodix_ts.0/switch_report_rate"
        MALI_PLATFORM="/sys/devices/platform/soc/13000000.mali/devfreq/13000000.mali"
        CPU_POLICIES="0 4 7"
        THERMAL_SCONFIG_PATH="/sys/devices/virtual/thermal/thermal_message/sconfig"
        BMS_TEMP_PATH="/sys/class/power_supply/bms/temp"
        CPU_GOV_FORCE=0
        GPU_GOV_FORCE=0
        ;;
esac

say "device: $DEVICE ($DEVICE_PROFILE profile)"

# ── ROM detection ────────────────────────────────────────────
# Standard Android/custom-ROM identifying properties. Not tied to any
# single ROM's source — hardware tweaks above already work regardless
# of ROM (they're kernel-level), this is purely for accurate reporting
# and so HyperOS-only features (PowerKeeper, deviceLevelList) know to
# stay quiet on AOSP-based ROMs instead of pretending to do something.
detect_rom() {
    hyperos=$(getprop ro.mi.os.version.name 2>/dev/null)
    miui=$(getprop ro.miui.ui.version.name 2>/dev/null)
    # ro.mi.os.version.name is only the short marketing name ("OS3.0");
    # the fuller incremental build string ("OS3.0.304.0WNLCNXM") people
    # actually look for lives in a separate prop that varies by build.
    hyperos_full=$(getprop ro.mi.os.version.incremental 2>/dev/null)
    [ -z "$hyperos_full" ] && hyperos_full=$(getprop ro.build.version.incremental 2>/dev/null)
    if [ -n "$hyperos" ]; then
        if [ -n "$hyperos_full" ]; then echo "HyperOS $hyperos_full"; else echo "HyperOS $hyperos"; fi
    elif [ -n "$miui" ]; then
        echo "MIUI $miui"
    elif [ -n "$(getprop ro.infinity.version 2>/dev/null)" ]; then
        echo "InfinityX $(getprop ro.infinity.version)"
    elif [ -n "$(getprop ro.lineage.version 2>/dev/null)" ]; then
        echo "LineageOS $(getprop ro.lineage.version)"
    elif [ -n "$(getprop ro.crdroid.version 2>/dev/null)" ]; then
        echo "crDroid $(getprop ro.crdroid.version)"
    elif [ -n "$(getprop ro.pixelexperience.version 2>/dev/null)" ]; then
        echo "PixelExperience $(getprop ro.pixelexperience.version)"
    elif [ -n "$(getprop ro.aospa.version 2>/dev/null)" ]; then
        echo "AOSPA $(getprop ro.aospa.version)"
    elif [ -n "$(getprop ro.build.version.opporom 2>/dev/null)" ] || [ -n "$(getprop ro.oplus.version 2>/dev/null)" ]; then
        echo "ColorOS-based $(getprop ro.build.version.opporom 2>/dev/null)"
    else
        echo "AOSP-based (Android $(getprop ro.build.version.release 2>/dev/null))"
    fi
}
ROM=$(detect_rom)
IS_HYPEROS=0
case "$ROM" in HyperOS*|MIUI*) IS_HYPEROS=1 ;; esac
say "rom: $ROM"

apply_hardware_tweaks() {
    echo "→ hardware tweaks"

    # Two different Goodix driver builds expose the touch report-rate
    # toggle under different node names — switch_report_rate is what
    # we've confirmed on HyperOS/duchamp; goodix_ts_report_rate is
    # reported on some AOSP-based builds. Detect whichever actually
    # exists on this device rather than hardcoding one — an absent
    # node just means write() skips it and logs "not writable" instead
    # of silently doing nothing on the wrong path.
    goodix_dir=$(dirname "$GOODIX_PATH")
    if [ -w "$goodix_dir/goodix_ts_report_rate" ]; then
        GOODIX_PATH="$goodix_dir/goodix_ts_report_rate"
    elif [ -w "$goodix_dir/switch_report_rate" ]; then
        GOODIX_PATH="$goodix_dir/switch_report_rate"
    fi
    # else: leave GOODIX_PATH as the profile default; write() will
    # report it as not-writable rather than fail silently.

    ht_save_node "$GOODIX_PATH"
    write "$GOODIX_PATH" "$REPORT_RATE_MODE"

    if [ "$GPU_GOV_FORCE" = "1" ]; then
        ht_save_node "$MALI_PLATFORM/governor"
        write "$MALI_PLATFORM/governor" "simple_ondemand"
    else
        ht_restore_node "$MALI_PLATFORM/governor" && say "  GPU governor restored"
        say "  GPU governor left as the vendor set it: $(cat "$MALI_PLATFORM/governor" 2>/dev/null)"
    fi

    for p in $CPU_POLICIES; do
        gov="/sys/devices/system/cpu/cpufreq/policy$p/scaling_governor"
        if [ "$CPU_GOV_FORCE" = "1" ]; then
            ht_save_node "$gov"
            write "$gov" "schedutil"
        else
            ht_restore_node "$gov" && say "  policy$p governor restored"
        fi
    done
    [ "$CPU_GOV_FORCE" = "1" ] || say "  CPU governor left as the vendor set it: $(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_governor 2>/dev/null)"

    ht_save_node "$THERMAL_SCONFIG_PATH"
    write "$THERMAL_SCONFIG_PATH" 6

    if [ "$SPOOF_BATTERY_TEMP" = "1" ]; then
        ht_save_node "$BMS_TEMP_PATH"
        write "$BMS_TEMP_PATH" 250
    else
        ht_restore_node "$BMS_TEMP_PATH" && say "  battery temp restored"
    fi
}

# ── Duchamp Tuning — real, working responsiveness tweaks ────
# Standard Linux/Android kernel tunables, not fabricated paths. Only
# runs on confirmed/named-experimental devices since it touches
# CPU/GPU scaling behavior specific to this chip family.
apply_duchamp_tuning() {
    echo "→ CPU/GPU tuning"
    if [ "$FAST_CPU_RESPONSE" = "1" ]; then
        # Kernels differ: Android-common/Qualcomm trees have separate
        # up_rate_limit_us / down_rate_limit_us; upstream (and the duchamp
        # 6.1 MediaTek kernel) only has a single rate_limit_us. Use whichever
        # exists, and report honestly if neither does.
        fast_done=0
        for p in $CPU_POLICIES; do
            sd="/sys/devices/system/cpu/cpufreq/policy$p/schedutil"
            if [ -w "$sd/up_rate_limit_us" ]; then
                ht_save_node "$sd/up_rate_limit_us"
                ht_save_node "$sd/down_rate_limit_us"
                write "$sd/up_rate_limit_us" 500
                write "$sd/down_rate_limit_us" 20000
                fast_done=$((fast_done + 1))
            elif [ -w "$sd/rate_limit_us" ]; then
                ht_save_node "$sd/rate_limit_us"
                write "$sd/rate_limit_us" 500
                fast_done=$((fast_done + 1))
            else
                warn "  policy$p: no writable schedutil rate limit (governor tunables missing)"
            fi
        done
        if [ "$fast_done" -gt 0 ]; then
            say "  fast CPU response: applied on $fast_done CPU cluster(s)"
        else
            warn "  fast CPU response: NOT applied — this kernel exposes no writable schedutil rate limit"
        fi
    else
        for p in $CPU_POLICIES; do
            sd="/sys/devices/system/cpu/cpufreq/policy$p/schedutil"
            for n in up_rate_limit_us down_rate_limit_us rate_limit_us; do
                ht_restore_node "$sd/$n" && say "  restored: policy$p $n"
            done
        done
    fi
    if [ "$GPU_FLOOR" = "1" ]; then
        freqs="$MALI_PLATFORM/available_frequencies"
        floor_file="$MALI_PLATFORM/min_freq"
        if [ -r "$freqs" ] && [ -w "$floor_file" ]; then
            # tr's SPACE class covers space/tab/newline/CR/FF/VT, unlike
            # a literal ' ' — some kernels delimit available_frequencies
            # with tabs or newlines instead of spaces.
            floor=$(tr '[:space:]' '\n' < "$freqs" | grep -v '^$' | sort -n | sed -n '2p')
            if [ -n "$floor" ]; then
                ht_save_node "$floor_file"
                write "$floor_file" "$floor"
            else
                warn "  GPU floor: couldn't parse available_frequencies"
            fi
        else
            warn "  GPU floor: available_frequencies not readable, skipping"
        fi
    fi
    if [ "$GPU_FLOOR" != "1" ]; then
        ht_restore_node "$MALI_PLATFORM/min_freq" && say "  GPU floor restored"
    fi
}

# ── PowerKeeper (MIUI/HyperOS only, safely no-ops on AOSP) ──
apply_powerkeeper() {
    echo "→ powerkeeper"
    if ! pm path com.miui.powerkeeper >/dev/null 2>&1; then
        say "  not present on this ROM, skipping"
        return
    fi
    # Remember whether PowerKeeper was already disabled before we touched it
    # (captured once) so turning the option off restores THAT, not a guess.
    ht_pk_save

    if [ "$DISABLE_POWERKEEPER" = "1" ]; then
        pm disable-user --user 0 "$HT_PK_COMP" >/dev/null 2>&1
        say "  disabled"
    else
        ht_pk_restore_comp
        say "  restored to its pre-HyperTouch state"
    fi

    # Opt-in: disabling the WHOLE package (also takes Game Turbo's
    # boost/Wild Boost profiles down — same package). Turning it back off
    # must explicitly re-enable the package; re-enabling only the
    # component (v3.1.0) left the package itself disabled.
    if [ "$POWERKEEPER_FULL_DISABLE" = "1" ]; then
        pm disable-user --user 0 "$HT_PK_PKG" >/dev/null 2>&1
        say "  fully disabled (unlocks apps HyperOS caps to 60Hz — also disables Game Turbo boost profiles, same package)"
    else
        ht_pk_restore_pkg
    fi
}

# ── Parallel Animation — real mechanism, confirmed working ──
# Not a made-up prop this time: deviceLevelList is a genuine
# Settings.System key HyperOS reads to decide which animation tier a
# device gets. duchamp/rodin are hardware-capable but classified below
# the tier that unlocks it — this raises the classification directly,
# no launcher/app modification involved.
apply_parallel_anim() {
    if [ "$PARALLEL_ANIM" != "1" ]; then
        ht_restore_setting system deviceLevelList settings_deviceLevelList && say "→ parallel animation: restored original deviceLevelList"
        return
    fi
    echo "→ parallel animation"
    if [ "$IS_HYPEROS" != "1" ]; then
        warn "  HyperOS-only feature, skipped on $ROM"
        return
    fi
    ht_save_setting system deviceLevelList settings_deviceLevelList
    settings put system deviceLevelList "v:1,c:3,g:3" 2>/dev/null
    # Best-effort live pickup: the animation-tier logic that reads this
    # key lives close to system_server, so there's no single userspace
    # process we can safely restart the way we can the launcher below.
    # Nudging system_server itself is a much bigger, riskier action
    # (briefly kills the whole UI) than this module should take without
    # being asked, so this stays reboot-recommended rather than
    # reboot-required — HyperOS may pick it up sooner on its own.
    say "  deviceLevelList set to v:1,c:3,g:3 (takes effect within HyperOS's own refresh window, reboot for guaranteed immediate effect)"
}

# ── Launcher animation rate — com.miui.home, no launcher edits ──
# Same idea as above but scoped specifically to the launcher: this is
# a Settings.System key the stock launcher itself reads at runtime, so
# it's a real way to influence com.miui.home's animation behavior
# without touching the launcher's own code (no Java/smali involved).
apply_launcher_anim() {
    if [ "$LAUNCHER_ANIM_RATE" != "1" ]; then
        if ht_restore_setting system miui_home_animation_rate settings_miui_home_animation_rate; then
            say "→ launcher animation rate: restored original"
            am force-stop com.miui.home 2>/dev/null
        fi
        return
    fi
    echo "→ launcher animation rate"
    if ! pm path com.miui.home >/dev/null 2>&1; then
        warn "  com.miui.home not present on this ROM, skipped"
        return
    fi
    ht_save_setting system miui_home_animation_rate settings_miui_home_animation_rate
    settings put system miui_home_animation_rate 1 2>/dev/null
    # Force-stopping the launcher is safe and instant — Android restarts
    # it automatically the moment it's needed (immediately, since it's
    # the home app), so this is a genuine hot-reload rather than
    # "restart it yourself or reboot."
    am force-stop com.miui.home 2>/dev/null
    say "  miui_home_animation_rate set to 1, launcher restarted to pick it up live"
}

# ── Force 120Hz — pins the display compositor to a fixed high refresh
# rate instead of letting it adapt down on static/low-motion content.
# Real battery cost, by design — same tradeoff as AOSP Developer
# Options' "Force peak refresh rate", just exposed here since HyperOS
# doesn't have its own equivalent toggle.
apply_force_120hz() {
    if [ "$FORCE_120HZ" != "1" ]; then
        _r1=1
        ht_restore_setting system min_refresh_rate settings_min_refresh_rate && _r1=0
        ht_restore_setting system peak_refresh_rate settings_peak_refresh_rate && _r1=0
        [ "$_r1" = "0" ] && say "→ force 120Hz: restored original refresh-rate settings"
        return
    fi
    echo "→ force 120Hz"

    # Highest refresh rate the panel can reach. `dumpsys display` lists every
    # supported mode explicitly, so it is preferred over SurfaceFlinger's
    # fps= (which on LTPO panels can show a transient mid-ramp rate).
    # Values are ROUNDED, not truncated: panels commonly report 119.99,
    # which truncation turned into 119 and wrongly rejected.
    max_hz=$(dumpsys display 2>/dev/null | grep -oE '(refreshRate|fps)=[0-9]+(\.[0-9]+)?' | cut -d= -f2 | awk '{printf "%d\n", $1+0.5}' | sort -rn | head -1)
    if [ -z "$max_hz" ]; then
        max_hz=$(dumpsys SurfaceFlinger 2>/dev/null | grep -oE 'fps=[0-9]+(\.[0-9]+)?' | cut -d= -f2 | awk '{printf "%d\n", $1+0.5}' | sort -rn | head -1)
    fi
    if [ -z "$max_hz" ]; then
        # Couldn't determine it. Don't treat "unknown" as "unsupported" —
        # try anyway; the read-back check below reports honestly.
        warn "  couldn't determine the panel's max refresh rate — trying anyway"
    elif [ "$max_hz" -lt 118 ] 2>/dev/null; then
        warn "  display tops out at ${max_hz}Hz, skipping"
        return
    fi

    ht_save_setting system min_refresh_rate settings_min_refresh_rate
    ht_save_setting system peak_refresh_rate settings_peak_refresh_rate
    settings put system min_refresh_rate 120 2>/dev/null
    settings put system peak_refresh_rate 120 2>/dev/null

    # Verify instead of assuming success. Re-read after a moment in case the
    # system immediately overwrites the values.
    sleep 1
    got_min=$(settings get system min_refresh_rate 2>/dev/null)
    got_peak=$(settings get system peak_refresh_rate 2>/dev/null)
    if is_120 "$got_min" && is_120 "$got_peak"; then
        say "  min/peak refresh rate pinned to 120Hz (verified) — real battery cost, by design"
    else
        warn "  120Hz NOT applied: read back min=${got_min:-unset} peak=${got_peak:-unset} (the system rejected or overrode it)"
        APPLY_RC=2
    fi
}
is_120() {
    case "$1" in 120|120.0|120.00|120.000000) return 0 ;; esac
    return 1
}

# ── VM / ZRAM — live counterpart to post-fs-data.sh's early-boot pass.
# post-fs-data.sh only runs once, at early boot, by the root framework's
# own design — it can't be re-invoked live. These specific sysfs/proc
# nodes are genuinely writable at any time though (not boot-only), so
# this mirrors that script's logic here too: toggling the setting takes
# effect immediately, and post-fs-data.sh still re-applies it on the
# next boot so it survives a reboot either way.
vm_nodes() {
    echo /proc/sys/vm/page-cluster
    echo /sys/block/zram0/max_comp_streams
    echo /proc/sys/vm/swappiness
    echo /proc/sys/vm/stat_interval
    for q in /sys/block/zram*/queue /sys/block/mmcblk*/queue /sys/block/sd*/queue; do
        [ -d "$q" ] && echo "$q/read_ahead_kb"
    done
    echo /proc/sys/kernel/sched_autogroup_enabled
}
apply_vm_tweaks() {
    if [ "$VM_TWEAKS_ENABLED" != "1" ]; then
        # Turning the option off restores what was there before.
        for n in $(vm_nodes); do
            ht_restore_node "$n" && say "→ VM: restored ${n##*/}"
        done
        return
    fi
    echo "→ VM / ZRAM (live)"
    # post-fs-data.sh may already have applied these at boot; it saves the
    # originals first, and ht_save_node never overwrites a capture.
    for n in $(vm_nodes); do ht_save_node "$n"; done
    write /proc/sys/vm/page-cluster 0
    write /sys/block/zram0/max_comp_streams 4
    write /proc/sys/vm/swappiness "$SWAPPINESS"
    write /proc/sys/vm/stat_interval 10
    for q in /sys/block/zram*/queue /sys/block/mmcblk*/queue /sys/block/sd*/queue; do
        [ -d "$q" ] || continue
        write "$q/read_ahead_kb" 128
    done
    write /proc/sys/kernel/sched_autogroup_enabled 1
}

# ── Priority Apps — background-restriction exemption, kernel-independent ──
apply_priority_apps() {
    apps="$PRIORITY_APPS"
    if [ "$TG_LAG_FIX" = "1" ]; then
        case " $apps " in
            *" org.telegram.messenger "*) ;;
            *) apps="${apps:+$apps }org.telegram.messenger" ;;
        esac
    fi

    # Apps removed from the list since the last run: undo ALL their changes
    # (Doze whitelist, both AppOps, standby bucket).
    for f in "$HT_STATE_DIR"/prio_*; do
        [ -f "$f" ] || continue
        old=${f##*/prio_}
        case " $apps " in *" $old "*) continue ;; esac
        ht_prio_restore "$old" && say "→ priority app removed, restored: $old"
    done

    [ -z "$apps" ] && return
    echo "→ priority apps"
    for pkg in $apps; do
        ht_valid_pkg "$pkg" || { warn "  invalid package name, skipping"; continue; }
        if ! pm path "$pkg" >/dev/null 2>&1; then
            warn "  not installed, skipping: $pkg"
            continue
        fi
        ht_prio_save "$pkg"     # originals first, only once per package
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

    # Read the actual touch report rate back from the node itself
    # rather than inferring "boosted"/"stock" from our own config —
    # the node reports a real value on read (confirmed format:
    # "touch report rate::480HZ"), so this shows what's genuinely
    # active, not just what we last told it to be.
    touch_rate="?"
    if [ -r "$GOODIX_PATH" ]; then
        touch_raw=$(cat "$GOODIX_PATH" 2>/dev/null)
        touch_parsed=$(echo "$touch_raw" | grep -oE '[0-9]+HZ' | head -1)
        if [ -n "$touch_parsed" ]; then
            touch_rate="$touch_parsed"
        elif echo "$touch_raw" | grep -qE '^[0-9]+$'; then
            # Some builds' nodes just echo back the raw mode index on
            # read instead of a formatted string — show that as-is
            # rather than inventing a Hz number we can't confirm.
            touch_rate="mode $touch_raw"
        fi
    fi

    mem_total_kb=$(awk '/MemTotal/{print $2}' /proc/meminfo 2>/dev/null)
    mem_avail_kb=$(awk '/MemAvailable/{print $2}' /proc/meminfo 2>/dev/null)
    if [ -n "$mem_total_kb" ] && [ -n "$mem_avail_kb" ]; then
        mem_used_gb=$(awk "BEGIN{printf \"%.1f\", ($mem_total_kb-$mem_avail_kb)/1048576}")
        mem_total_gb=$(awk "BEGIN{printf \"%.1f\", $mem_total_kb/1048576}")
        ram="${mem_used_gb}/${mem_total_gb}GB"
    else
        ram="?"
    fi

    desc="Touch: $touch_rate · RAM $ram · $ROM · $DEVICE_PROFILE"
    # ROM strings come from system props: strip characters that are special
    # in a sed replacement so they can't corrupt module.prop.
    desc=$(printf '%s' "$desc" | tr -d '|&\\')
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
# Capture PowerKeeper's pre-HyperTouch state before anything else runs.
ht_pk_save

if [ "$DEVICE_PROFILE" = "confirmed" ] || [ "$DEVICE_PROFILE" = "experimental-named" ] || [ "$FORCE_EXPERIMENTAL" = "1" ]; then
    apply_hardware_tweaks
    apply_duchamp_tuning
else
    warn "device '$DEVICE' has no confirmed or named-experimental profile — hardware tweaks skipped (set FORCE_EXPERIMENTAL=1 to try duchamp's paths anyway)"
fi

apply_powerkeeper
apply_parallel_anim
apply_launcher_anim
apply_force_120hz
apply_vm_tweaks
apply_priority_apps
update_live_info

echo "── done ──"
log -p i -t "$LOGTAG" "apply.sh completed (profile=$DEVICE_PROFILE, rc=$APPLY_RC)."

[ "$HT_LOCK_HELD" != "1" ] && ht_lock_release
exit "$APPLY_RC"
