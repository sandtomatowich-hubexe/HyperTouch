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
#                                 fast-cpu | gpu-floor | miui-opt | tg-fix
#   action.sh disable <feature>   (same feature names)
#   action.sh reset               restore settings.conf to shipped defaults
#   action.sh revert              temporarily undo tweaks (settings.conf kept)
#   action.sh help                show this text

MODDIR=${0%/*}
CONF="$MODDIR/settings.conf"
DEFAULT_CONF="$MODDIR/settings.conf.default"

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
        battery-spoof)     echo SPOOF_BATTERY_TEMP ;;
        fast-cpu)          echo FAST_CPU_RESPONSE ;;
        gpu-floor)         echo GPU_FLOOR ;;
        miui-opt)          echo DISABLE_MIUI_OPT ;;
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
    echo "  battery spoof  : $(conf_get SPOOF_BATTERY_TEMP)  (0=off, real temp reported)"
    echo "  fast cpu resp. : $(conf_get FAST_CPU_RESPONSE)"
    echo "  gpu floor      : $(conf_get GPU_FLOOR)"
    echo "  smooth touch   : $(conf_get SMOOTH_TOUCH_MODE)  (0=stock 1=fast 2=instant)"
    echo "  miui opt off   : $(conf_get DISABLE_MIUI_OPT)  (experimental)"
    echo "  priority apps  : $(conf_get PRIORITY_APPS)"
    echo "  tg lag fix     : $(conf_get TG_LAG_FIX)  (experimental)"
}

cmd_enable() {
    key=$(feature_key "$1")
    if [ -z "$key" ]; then
        echo "unknown feature '$1'. try: boost, powerkeeper, battery-spoof, fast-cpu, gpu-floor, miui-opt, tg-fix"
        exit 1
    fi
    conf_set "$key" 1
    echo "enabled: $1"
    sh "$MODDIR/apply.sh"
}

cmd_disable() {
    key=$(feature_key "$1")
    if [ -z "$key" ]; then
        echo "unknown feature '$1'. try: boost, powerkeeper, battery-spoof, fast-cpu, gpu-floor, miui-opt, tg-fix"
        exit 1
    fi
    conf_set "$key" 0
    echo "disabled: $1"
    sh "$MODDIR/apply.sh"
}

cmd_reset() {
    if [ -f "$DEFAULT_CONF" ]; then
        cp "$DEFAULT_CONF" "$CONF"
        echo "settings.conf restored to shipped defaults."
        sh "$MODDIR/apply.sh"
    else
        echo "settings.conf.default not found — can't reset. Reinstall the module to restore it."
        exit 1
    fi
}

cmd_revert() {
    echo "Reverting to stock behavior for this session (settings.conf is NOT changed)..."
    pm enable com.miui.powerkeeper/.statemachine.PowerStateMachineService >/dev/null 2>&1
    settings put global window_animation_scale 1.0 2>/dev/null
    settings put global transition_animation_scale 1.0 2>/dev/null
    settings put global animator_duration_scale 1.0 2>/dev/null
    if [ -w /sys/devices/platform/goodix_ts.0/switch_report_rate ]; then
        echo 0 > /sys/devices/platform/goodix_ts.0/switch_report_rate 2>/dev/null
    fi
    apps="$(conf_get PRIORITY_APPS)"
    [ "$(conf_get TG_LAG_FIX)" = "1" ] && apps="$apps org.telegram.messenger"
    for pkg in $apps; do
        [ -z "$pkg" ] && continue
        dumpsys deviceidle whitelist "-$pkg" >/dev/null 2>&1
    done
    echo "Reverted. Run 'action.sh' again (or tap Apply/Action) to reapply your saved settings."
}

cmd_help() {
    cat << 'EOF'
HyperTouch management CLI

  action.sh                    re-apply current settings
  action.sh status              show current settings + device profile
  action.sh enable <feature>    boost | powerkeeper | battery-spoof |
                                fast-cpu | gpu-floor | miui-opt | tg-fix
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
