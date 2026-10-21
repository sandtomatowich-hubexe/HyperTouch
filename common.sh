#!/system/bin/sh
# HyperTouch shared helpers. SOURCED by apply.sh, action.sh, post-fs-data.sh
# and uninstall.sh — never executed on its own. Callers must set $MODDIR
# first.
#
# Everything that has to behave identically in more than one script lives
# here: the safe settings.conf loader, package-name validation, and the
# "remember the original value, restore it later" state helpers. Keeping a
# single copy is what stops apply / revert / uninstall from drifting apart
# (which is how most of the v3.1.0 restore bugs happened).

HT_STATE_DIR="$MODDIR/.state"
HT_TAG="HyperTouch"
HT_UNSET_MARK="__HT_UNSET__"

# ── logging (callers may override say/warn; these are the fallbacks) ──
ht_log_w() { log -p w -t "$HT_TAG" "$1" 2>/dev/null; }

# ─────────────────────────────────────────────────────────────────────
# Package-name validation
# ─────────────────────────────────────────────────────────────────────
# Android package names: dot-separated segments of [A-Za-z0-9_], at least
# two segments, no empty segments. Anything else is rejected — these
# names end up in shell commands that run as root.
ht_valid_pkg() {
    case "$1" in
        ""|*[!A-Za-z0-9_.]*) return 1 ;;
        .*|*.|*..*) return 1 ;;
        *.*) ;;
        *) return 1 ;;
    esac
    [ "${#1}" -le 255 ] || return 1
    return 0
}

# ─────────────────────────────────────────────────────────────────────
# Safe settings.conf loader
# ─────────────────────────────────────────────────────────────────────
# settings.conf used to be `.`-sourced, i.e. executed as root. A malformed
# or malicious PRIORITY_APPS value could therefore run arbitrary commands.
# This reader never executes the file: it parses KEY=VALUE lines, accepts
# only known keys, validates every value, and assigns with eval ONLY after
# the key has matched a fixed whitelist (the value is passed by variable
# reference, so its contents are never re-parsed as shell).

# Trims whitespace and any number of surrounding quote characters (older
# WebUI builds stacked an extra pair of quotes on every save). Result is
# left in $HT_CLEAN.
ht_clean_val() {
    HT_CLEAN="$1"
    while :; do
        case "$HT_CLEAN" in
            " "*|"	"*|\"*|\'*) HT_CLEAN=${HT_CLEAN#?} ;;
            *) break ;;
        esac
    done
    while :; do
        case "$HT_CLEAN" in
            *" "|*"	"|*\"|*\') HT_CLEAN=${HT_CLEAN%?} ;;
            *) break ;;
        esac
    done
}

# Reads $1 and overwrites the caller's defaults for every valid key found.
ht_load_conf() {
    _hc_file="$1"
    [ -f "$_hc_file" ] || return 0
    _hc_cr=$(printf '\r')
    while IFS= read -r _hc_line || [ -n "$_hc_line" ]; do
        _hc_line=${_hc_line%"$_hc_cr"}
        case "$_hc_line" in
            ""|"#"*|" "*|"	"*) continue ;;
            *=*) ;;
            *) continue ;;
        esac
        _hc_key=${_hc_line%%=*}
        ht_clean_val "${_hc_line#*=}"
        _hc_val="$HT_CLEAN"
        case "$_hc_key" in
            REPORT_RATE_MODE|DISABLE_POWERKEEPER|POWERKEEPER_FULL_DISABLE|SPOOF_BATTERY_TEMP|FAST_CPU_RESPONSE|GPU_FLOOR|PARALLEL_ANIM|LAUNCHER_ANIM_RATE|FORCE_120HZ|TG_LAG_FIX|VM_TWEAKS_ENABLED|FORCE_EXPERIMENTAL)
                case "$_hc_val" in
                    0|1) eval "$_hc_key=\$_hc_val" ;;
                    *) ht_log_w "settings.conf: ignoring invalid value for $_hc_key" ;;
                esac
                ;;
            SWAPPINESS)
                case "$_hc_val" in
                    ""|*[!0-9]*) ht_log_w "settings.conf: ignoring invalid SWAPPINESS" ;;
                    *)
                        if [ "${#_hc_val}" -le 3 ] && [ "$_hc_val" -le 200 ]; then
                            SWAPPINESS="$_hc_val"
                        else
                            ht_log_w "settings.conf: SWAPPINESS out of range, ignored"
                        fi
                        ;;
                esac
                ;;
            PRIORITY_APPS)
                _hc_ok=""
                set -f
                for _hc_p in $_hc_val; do
                    if ht_valid_pkg "$_hc_p"; then
                        case " $_hc_ok " in
                            *" $_hc_p "*) ;;
                            *) _hc_ok="${_hc_ok:+$_hc_ok }$_hc_p" ;;
                        esac
                    else
                        ht_log_w "settings.conf: dropped invalid package name in PRIORITY_APPS"
                    fi
                done
                set +f
                PRIORITY_APPS="$_hc_ok"
                ;;
            *) ;;   # unknown / legacy keys (CONF_VERSION, SMOOTH_TOUCH_MODE…) are ignored
        esac
    done < "$_hc_file"
}

# ─────────────────────────────────────────────────────────────────────
# Original-value state: sysfs / proc nodes
# ─────────────────────────────────────────────────────────────────────
# One value file per node under $HT_STATE_DIR, named by the node path with
# "/" → "_". That encoding is LOSSY (real paths contain "_" themselves, e.g.
# up_rate_limit_us), so decoding the name back into a path is impossible —
# which is exactly the v3.1.0 revert bug. The real path is therefore stored
# in a "<name>.node" sidecar file and revert reads that instead.

ht_node_key() { printf '%s' "$1" | tr '/' '_'; }

# Save the node's current value ONCE (never overwrite an existing capture).
ht_save_node() {
    _hn_node="$1"
    [ -r "$_hn_node" ] || return 1
    _hn_dst="$HT_STATE_DIR/$(ht_node_key "$_hn_node")"
    mkdir -p "$HT_STATE_DIR" 2>/dev/null
    if [ ! -f "$_hn_dst" ]; then
        if cat "$_hn_node" > "$_hn_dst.tmp" 2>/dev/null; then
            mv -f "$_hn_dst.tmp" "$_hn_dst" 2>/dev/null
        else
            rm -f "$_hn_dst.tmp" 2>/dev/null
            return 1
        fi
    fi
    # Also (re)creates the sidecar for state captured by v3.1.0, which had none.
    [ -f "$_hn_dst.node" ] || printf '%s\n' "$_hn_node" > "$_hn_dst.node" 2>/dev/null
    return 0
}

# Restore one node from its saved value, then forget the capture.
# 0 = restored, 1 = nothing to do / couldn't, 2 = saved value isn't writable
# as-is (touch report-rate nodes read back as "touch report rate::480HZ").
ht_restore_node() {
    _hr_node="$1"
    _hr_dst="$HT_STATE_DIR/$(ht_node_key "$_hr_node")"
    [ -s "$_hr_dst" ] || return 1
    [ -w "$_hr_node" ] || return 1
    _hr_val=$(cat "$_hr_dst" 2>/dev/null)
    case "$_hr_val" in
        *::*|*[Hh][Zz]*) return 2 ;;
    esac
    if echo "$_hr_val" > "$_hr_node" 2>/dev/null; then
        rm -f "$_hr_dst" "$_hr_dst.node" 2>/dev/null
        return 0
    fi
    return 1
}

ht_drop_node_state() {
    _hd_dst="$HT_STATE_DIR/$(ht_node_key "$1")"
    rm -f "$_hd_dst" "$_hd_dst.node" 2>/dev/null
}

# Restore every node that has a sidecar. Prints one line per node restored.
ht_restore_all_nodes() {
    [ -d "$HT_STATE_DIR" ] || return 0
    for _ha_sc in "$HT_STATE_DIR"/*.node; do
        [ -f "$_ha_sc" ] || continue
        _ha_node=$(cat "$_ha_sc" 2>/dev/null)
        case "$_ha_node" in
            /sys/*|/proc/sys/*) ;;
            *) continue ;;
        esac
        ht_restore_node "$_ha_node" && echo "  restored: ${_ha_node##*/}"
    done
}

# Touch report-rate nodes read back a formatted string ("touch report rate::
# 480HZ") that can't be written back as-is. The write values are verified on
# real hardware: 1 reads back 480HZ, 0 reads back 240HZ. So the saved readback
# is mapped back to the write value that reproduces it; anything unrecognised
# falls back to 0 (stock).
ht_restore_report_rate() {
    for _hq_node in /sys/devices/platform/goodix_ts.0/goodix_ts_report_rate /sys/devices/platform/goodix_ts.0/switch_report_rate; do
        _hq_dst="$HT_STATE_DIR/$(ht_node_key "$_hq_node")"
        [ -f "$_hq_dst" ] || continue
        _hq_saved=$(cat "$_hq_dst" 2>/dev/null)
        case "$_hq_saved" in
            *480[Hh][Zz]*) _hq_val=1 ;;
            *240[Hh][Zz]*) _hq_val=0 ;;
            *) _hq_val=0 ;;
        esac
        if [ -w "$_hq_node" ] && echo "$_hq_val" > "$_hq_node" 2>/dev/null; then
            rm -f "$_hq_dst" "$_hq_dst.node" 2>/dev/null
            echo "  restored: ${_hq_node##*/} = $_hq_val"
        fi
    done
}

# ─────────────────────────────────────────────────────────────────────
# Original-value state: Settings provider
# ─────────────────────────────────────────────────────────────────────
# $1 namespace  $2 key  $3 state file name
# An UNSET key is recorded with a marker so restore can `settings delete`
# it instead of leaving our value behind (v3.1.0 stored nothing for unset
# keys, so e.g. the 120Hz pin could never be undone).
ht_save_setting() {
    _hs_dst="$HT_STATE_DIR/$3"
    [ -f "$_hs_dst" ] && return 0
    _hs_val=$(settings get "$1" "$2" 2>/dev/null) || return 1
    case "$_hs_val" in
        *rror*|*"find service"*|*xception*) return 1 ;;   # settings service not ready — don't record garbage
    esac
    mkdir -p "$HT_STATE_DIR" 2>/dev/null
    if [ -z "$_hs_val" ] || [ "$_hs_val" = "null" ]; then
        echo "$HT_UNSET_MARK" > "$_hs_dst"
    else
        echo "$_hs_val" > "$_hs_dst"
    fi
}

ht_restore_setting() {
    _hu_dst="$HT_STATE_DIR/$3"
    [ -f "$_hu_dst" ] || return 1
    _hu_val=$(cat "$_hu_dst" 2>/dev/null)
    if [ "$_hu_val" = "$HT_UNSET_MARK" ]; then
        settings delete "$1" "$2" >/dev/null 2>&1 || return 1
    else
        [ -n "$_hu_val" ] || return 1
        settings put "$1" "$2" "$_hu_val" >/dev/null 2>&1 || return 1
    fi
    rm -f "$_hu_dst" 2>/dev/null
    return 0
}

# ─────────────────────────────────────────────────────────────────────
# Original-value state: PowerKeeper
# ─────────────────────────────────────────────────────────────────────
HT_PK_PKG="com.miui.powerkeeper"
HT_PK_COMP="com.miui.powerkeeper/.statemachine.PowerStateMachineService"

# Capture whether the package / the state-machine component were already
# disabled BEFORE HyperTouch touched them (captured once).
# If .state already holds anything, a previous HyperTouch version has been
# running on this device and may itself have disabled PowerKeeper, so the
# only safe assumption is "was enabled" (the v3.1.0 behaviour).
ht_pk_save() {
    [ -f "$HT_STATE_DIR/pk_pkg" ] && return 0
    pm path "$HT_PK_PKG" >/dev/null 2>&1 || return 0
    _hp_pkg=enabled; _hp_comp=enabled
    if [ -z "$(ls -A "$HT_STATE_DIR" 2>/dev/null)" ]; then
        pm list packages -d 2>/dev/null | grep -qx "package:$HT_PK_PKG" && _hp_pkg=disabled
        if dumpsys package "$HT_PK_PKG" 2>/dev/null | awk '
                /disabledComponents:/ {f=1; next}
                f && /^[[:space:]]*[A-Za-z]+:/ {f=0}
                f && /PowerStateMachineService/ {found=1}
                END {exit !found}'; then
            _hp_comp=disabled
        fi
    fi
    mkdir -p "$HT_STATE_DIR" 2>/dev/null
    echo "$_hp_comp" > "$HT_STATE_DIR/pk_comp"
    echo "$_hp_pkg" > "$HT_STATE_DIR/pk_pkg"
}

# Re-enable only if it was enabled before HyperTouch (default: enabled).
ht_pk_restore_pkg() {
    pm path "$HT_PK_PKG" >/dev/null 2>&1 || return 0
    [ "$(cat "$HT_STATE_DIR/pk_pkg" 2>/dev/null)" = "disabled" ] && return 0
    pm enable "$HT_PK_PKG" >/dev/null 2>&1
}
ht_pk_restore_comp() {
    pm path "$HT_PK_PKG" >/dev/null 2>&1 || return 0
    [ "$(cat "$HT_STATE_DIR/pk_comp" 2>/dev/null)" = "disabled" ] && return 0
    pm enable "$HT_PK_COMP" >/dev/null 2>&1
}

# ─────────────────────────────────────────────────────────────────────
# Original-value state: Priority Apps
# ─────────────────────────────────────────────────────────────────────
# Applying a priority app changes FOUR things: the Doze whitelist, two
# AppOps, and the standby bucket. All four must be undone.
ht_prio_save() {
    _hy_f="$HT_STATE_DIR/prio_$1"
    [ -f "$_hy_f" ] && return 0
    mkdir -p "$HT_STATE_DIR" 2>/dev/null
    _hy_wl=0
    dumpsys deviceidle whitelist 2>/dev/null | grep -qF ",$1," && _hy_wl=1
    _hy_b=$(am get-standby-bucket "$1" 2>/dev/null | tr -dc '0-9')
    case "$_hy_b" in 5|10|20|30|40|45|50) ;; *) _hy_b="" ;; esac
    printf 'whitelisted=%s\nbucket=%s\n' "$_hy_wl" "$_hy_b" > "$_hy_f"
}

ht_prio_restore() {
    ht_valid_pkg "$1" || return 1
    _hz_f="$HT_STATE_DIR/prio_$1"
    _hz_wl=0; _hz_b=""
    if [ -f "$_hz_f" ]; then
        _hz_wl=$(sed -n 's/^whitelisted=//p' "$_hz_f" | head -1)
        _hz_b=$(sed -n 's/^bucket=//p' "$_hz_f" | head -1)
    fi
    # Leave the Doze whitelist alone if the app was already on it before us.
    [ "$_hz_wl" = "1" ] || dumpsys deviceidle whitelist "-$1" >/dev/null 2>&1
    cmd appops set "$1" RUN_IN_BACKGROUND default >/dev/null 2>&1
    cmd appops set "$1" RUN_ANY_IN_BACKGROUND default >/dev/null 2>&1
    case "$_hz_b" in
        5|10|20|30|40|45|50) am set-standby-bucket "$1" "$_hz_b" >/dev/null 2>&1 ;;
        *) am set-standby-bucket "$1" working_set >/dev/null 2>&1 ;;
    esac
    rm -f "$_hz_f" 2>/dev/null
    return 0
}

# Restore every package that has a saved prio_* capture.
ht_prio_restore_all() {
    [ -d "$HT_STATE_DIR" ] || return 0
    for _hw_f in "$HT_STATE_DIR"/prio_*; do
        [ -f "$_hw_f" ] || continue
        _hw_pkg=${_hw_f##*/prio_}
        ht_prio_restore "$_hw_pkg" && echo "  restored priority app: $_hw_pkg"
    done
}
