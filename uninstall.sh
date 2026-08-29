#!/system/bin/sh
# Restores stock behavior on removal. Sysfs tweaks (report rate,
# governors, thermal) reset naturally on next boot once this module's
# service.sh no longer runs — but Settings-provider and Doze/App
# Standby changes persist independently of the module, so they need
# to be explicitly reverted here.

CONF="${0%/*}/settings.conf"

pm enable com.miui.powerkeeper/.statemachine.PowerStateMachineService >/dev/null 2>&1

if command -v resetprop >/dev/null 2>&1; then
    resetprop persist.sys.miui_optimization true >/dev/null 2>&1
else
    setprop persist.sys.miui_optimization true >/dev/null 2>&1
fi

settings put global window_animation_scale 1.0 2>/dev/null
settings put global transition_animation_scale 1.0 2>/dev/null
settings put global animator_duration_scale 1.0 2>/dev/null

if [ -f "$CONF" ]; then
    PRIORITY_APPS=$(grep "^PRIORITY_APPS=" "$CONF" | tail -1 | cut -d= -f2-)
    TG_LAG_FIX=$(grep "^TG_LAG_FIX=" "$CONF" | tail -1 | cut -d= -f2-)
    apps="$PRIORITY_APPS"
    [ "$TG_LAG_FIX" = "1" ] && apps="$apps org.telegram.messenger"
    for pkg in $apps; do
        [ -z "$pkg" ] && continue
        dumpsys deviceidle whitelist "-$pkg" >/dev/null 2>&1
    done
fi
