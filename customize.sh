#!/system/bin/sh

# ==========================================================
# HyperTouch
# Advanced Touch Optimization Framework
# Target: duchamp
# Author: Sep @C0RS0N
# ==========================================================

ui_print " "
ui_print "╔════════════════════════════════╗"
ui_print "║          HyperTouch             ║"
ui_print "║     Touch Optimization Engine   ║"
ui_print "║            By Sep             ║"
ui_print "╚════════════════════════════════╝"
ui_print " "

# Device information
MODEL=$(getprop ro.product.model)
DEVICE=$(getprop ro.product.device)
BRAND=$(getprop ro.product.brand)
ANDROID=$(getprop ro.build.version.release)
KERNEL=$(uname -r)

UI=$(getprop ro.mi.os.version.name)
[ -z "$UI" ] && UI=$(getprop ro.miui.ui.version.name)

ui_print "┌─ Device Environment"
ui_print "│ Brand     : $BRAND"
ui_print "│ Model     : $MODEL"
ui_print "│ Codename  : $DEVICE"
ui_print "│ Android   : $ANDROID"
ui_print "│ UI        : $UI"
ui_print "│ Kernel    : $KERNEL"
ui_print "└──────────────────────────────"
ui_print " "

# Compatibility

if [ "$DEVICE" = "duchamp" ]; then
    ui_print "[✓] Target device verified"
else
    ui_print "[!] Unknown device detected"
    ui_print "    HyperTouch was designed for duchamp"
    ui_print "    Continuing with compatibility mode"
fi

ui_print " "

# Root manager detection

if [ -d "/data/adb/ksu" ]; then
    ROOT="KernelSU"
elif [ -d "/data/adb/magisk" ]; then
    ROOT="Magisk"
else
    ROOT="Unknown"
fi

ui_print "[✓] Root environment : $ROOT"

ui_print " "
ui_print " Installing components..."
ui_print " "

# Permission setup

FILES="
$MODPATH/action.sh
$MODPATH/apply.sh
$MODPATH/tools/probe_touch.sh
"

for file in $FILES; do
    if [ -f "$file" ]; then
        set_perm "$file" 0 0 0755
        ui_print "[✓] Secured $(basename $file)"
    else
        ui_print "[!] Missing $(basename $file)"
    fi
done

ui_print " "

# Safety preparation

mkdir -p "$MODPATH/logs"
mkdir -p "$MODPATH/backup"

ui_print "[✓] Safety environment initialized"
ui_print "[✓] Backup directory prepared"

ui_print " "

# Final

ui_print "╔════════════════════════════════╗"
ui_print "║        Installation Done        ║"
ui_print "╚════════════════════════════════╝"

ui_print " "
ui_print " HyperTouch is ready."
ui_print " "
ui_print " Recommended:"
ui_print " • Reboot for full activation"
ui_print " • Use WebUI for live tuning"
ui_print " • Use Action button for reload"
ui_print " "

ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ui_print "        Safe • Clean • Tuned"
ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ui_print " "