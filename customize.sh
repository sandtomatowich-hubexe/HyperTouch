#!/system/bin/sh

# --- UI banner ---
ui_print "————————————————————————————————"
ui_print "  HyperTouch — duchamp touch tuning"
ui_print "  by Sep"
ui_print "————————————————————————————————"

MODEL=$(getprop ro.product.model)
CODENAME=$(getprop ro.product.device)
ANDROID_VER=$(getprop ro.build.version.release)
OS_VER=$(getprop ro.mi.os.version.name)
[ -z "$OS_VER" ] && OS_VER=$(getprop ro.miui.ui.version.name)
KERNEL_VER=$(uname -r)

ui_print " Device   : $MODEL ($CODENAME)"
ui_print " Android  : $ANDROID_VER"
ui_print " OS/UI    : $OS_VER"
ui_print " Kernel   : $KERNEL_VER"
ui_print "————————————————————————————————"

if [ "$CODENAME" = "duchamp" ]; then
  ui_print " Device profile: confirmed — full tweak set enabled."
else
  ui_print " Device profile: experimental (no confirmed profile"
  ui_print " for '$CODENAME' yet). Kernel-independent features"
  ui_print " (Smooth Touch, Priority Apps, PowerKeeper) still work;"
  ui_print " hardware-specific tweaks are skipped unless you set"
  ui_print " FORCE_EXPERIMENTAL=1 in settings.conf. See README."
fi
ui_print "————————————————————————————————"

ui_print " Installing..."

# Preserve settings across updates: install_module extracts into a
# fresh staging path, so the currently-live module (if any) is still
# readable here — carry its settings.conf forward instead of
# resetting the user back to shipped defaults on every update.
LIVE_CONF="/data/adb/modules/hypertouch/settings.conf"
if [ -f "$LIVE_CONF" ] && [ "$LIVE_CONF" != "$MODPATH/settings.conf" ]; then
  ui_print " Existing install found — keeping your saved settings."
  cp "$LIVE_CONF" "$MODPATH/settings.conf"
else
  ui_print " Fresh install — using default settings."
fi

# post-fs-data.sh / service.sh / system.prop / uninstall.sh get their
# permissions and SELinux context set automatically by install_module.
# action.sh, apply.sh, and probe_touch.sh aren't "known" filenames to
# Magisk/KernelSU, so they need it set explicitly.
set_perm "$MODPATH/action.sh" 0 0 0755
set_perm "$MODPATH/apply.sh" 0 0 0755
set_perm "$MODPATH/tools/probe_touch.sh" 0 0 0755
set_perm "$MODPATH/tools/probe_device.sh" 0 0 0755

ui_print " Done. Reboot to apply, or use the WebUI / Action"
ui_print " button afterwards to re-apply without rebooting."
ui_print "————————————————————————————————"
