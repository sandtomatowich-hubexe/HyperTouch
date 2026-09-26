#!/system/bin/sh
# HyperTouch installer.
# Runs inside the flashing environment (Magisk/KernelSU/APatch app or
# recovery) via install_module. $MODPATH is the staging directory this
# script's own files were extracted into; ui_print writes to whatever
# on-screen flash log the manager shows.

banner() { ui_print "————————————————————————————————"; }

banner
ui_print "  HyperTouch — touch + performance tuning"
ui_print "  by Sep"
banner

# ── Environment ──────────────────────────────────────────────
MODEL=$(getprop ro.product.model)
CODENAME=$(getprop ro.product.device)
ANDROID_VER=$(getprop ro.build.version.release)
OS_VER=$(getprop ro.mi.os.version.name)
[ -z "$OS_VER" ] && OS_VER=$(getprop ro.miui.ui.version.name)
[ -z "$OS_VER" ] && OS_VER="AOSP-based"
KERNEL_VER=$(uname -r)
ARCH=$(getprop ro.product.cpu.abi)

ui_print " Device   : $MODEL ($CODENAME)"
ui_print " Android  : $ANDROID_VER"
ui_print " OS/UI    : $OS_VER"
ui_print " Kernel   : $KERNEL_VER"
ui_print " ABI      : $ARCH"
banner

# ── Root manager detection ───────────────────────────────────
# KSU_VER/APATCH are set by KernelSU/APatch's own install_module
# wrapper before sourcing this script; Magisk sets neither. This is
# informational only — every manager that can flash a module can run
# apply.sh/action.sh, since those are plain shell — but the WebUI
# specifically needs a manager with an in-app KSU-bridge WebView
# (KernelSU Next, MMRL, or APatch's own), not Magisk's, which has none.
if [ -n "$KSU_VER" ]; then
  MANAGER="KernelSU"
  [ -n "$KSU_VER_CODE" ] && MANAGER="KernelSU (v$KSU_VER_CODE)"
  WEBUI_OK=1
elif [ -n "$APATCH_VER" ]; then
  MANAGER="APatch"
  WEBUI_OK=1
elif [ -d "/data/adb/magisk" ]; then
  MANAGER="Magisk"
  WEBUI_OK=0
else
  MANAGER="unknown"
  WEBUI_OK=0
fi
ui_print " Root manager: $MANAGER"
if [ "$WEBUI_OK" != "1" ]; then
  ui_print " Note: the WebUI needs a KSU-bridge WebView (KernelSU Next,"
  ui_print " MMRL, or APatch's own) to control anything. action.sh from"
  ui_print " a root shell always works regardless of manager."
fi
banner

# ── Architecture guard ───────────────────────────────────────
# Every hardware path this module touches is sysfs text I/O via plain
# POSIX shell (write()/cat) — no compiled binaries, so nothing here is
# actually arch-specific. This check exists only to catch the case of
# someone flashing on something that isn't a phone-class arm64 device
# at all, where the sysfs layout this module targets won't exist.
case "$ARCH" in
  arm64-v8a) ;;
  armeabi*)
    ui_print " Warning: 32-bit ABI ($ARCH) — untested. The touch/GPU/"
    ui_print " thermal sysfs paths this module targets were found on"
    ui_print " arm64 duchamp/rodin hardware specifically."
    ;;
  *)
    ui_print " Warning: unrecognized ABI ($ARCH) — this module targets"
    ui_print " Poco X6 Pro / X7 Pro hardware. Kernel-independent features"
    ui_print " (Priority Apps, PowerKeeper) will still work; hardware"
    ui_print " tweaks will likely no-op safely rather than do anything."
    ;;
esac

# ── Device profile ───────────────────────────────────────────
case "$CODENAME" in
  duchamp)
    ui_print " Device profile: confirmed — Poco X6 Pro, full tweak set."
    ;;
  rodin)
    ui_print " Device profile: experimental (named) — Poco X7 Pro."
    ui_print " Hardware tweaks run using duchamp's paths as a starting"
    ui_print " guess (same CPU cluster topology, unconfirmed touch/GPU"
    ui_print " paths). Kernel-independent features always work."
    ;;
  *)
    ui_print " Device profile: experimental (no confirmed or named"
    ui_print " profile for '$CODENAME' yet). Kernel-independent features"
    ui_print " (Priority Apps, PowerKeeper) still work; hardware-specific"
    ui_print " tweaks are skipped unless you set FORCE_EXPERIMENTAL=1"
    ui_print " in settings.conf. See README."
    ;;
esac
banner

# ── Touch report-rate node probe ─────────────────────────────
# apply.sh auto-detects this at apply-time too (see apply_hardware_
# tweaks), but checking here means the flash log itself tells you
# right away whether report-rate boost has anything to attach to on
# this exact build, instead of only finding out after first apply.
GOODIX_DIR="/sys/devices/platform/goodix_ts.0"
if [ -e "$GOODIX_DIR/goodix_ts_report_rate" ]; then
  ui_print " Touch report-rate node: goodix_ts_report_rate (found)"
elif [ -e "$GOODIX_DIR/switch_report_rate" ]; then
  ui_print " Touch report-rate node: switch_report_rate (found)"
else
  ui_print " Touch report-rate node: not found on this build — boosted"
  ui_print " report rate will safely no-op. Run tools/probe_device.sh as"
  ui_print " root and share the output on GitHub if you'd like this"
  ui_print " chased down for your ROM."
fi
banner

ui_print " Installing..."

# Preserve settings across updates: install_module extracts into a
# fresh staging path, so the currently-live module (if any) is still
# readable here — carry its settings.conf and webui/ui.conf forward
# instead of resetting the user back to shipped defaults on every
# update.
LIVE_DIR="/data/adb/modules/hypertouch"
if [ -f "$LIVE_DIR/settings.conf" ] && [ "$LIVE_DIR/settings.conf" != "$MODPATH/settings.conf" ]; then
  ui_print " Existing install found — keeping your saved settings."
  cp "$LIVE_DIR/settings.conf" "$MODPATH/settings.conf"
  if [ -f "$LIVE_DIR/webui/ui.conf" ]; then
    mkdir -p "$MODPATH/webui"
    cp "$LIVE_DIR/webui/ui.conf" "$MODPATH/webui/ui.conf"
    ui_print " Carried over your WebUI appearance settings too."
  fi
else
  ui_print " Fresh install — using default settings."
fi

# post-fs-data.sh / service.sh / system.prop / uninstall.sh get their
# permissions and SELinux context set automatically by install_module.
# action.sh, apply.sh, lock.sh, and probe_device.sh aren't "known"
# filenames to Magisk/KernelSU, so they need it set explicitly.
set_perm "$MODPATH/action.sh" 0 0 0755
set_perm "$MODPATH/apply.sh" 0 0 0755
set_perm "$MODPATH/lock.sh" 0 0 0755
set_perm "$MODPATH/tools/probe_device.sh" 0 0 0755
[ -f "$MODPATH/tools/probe_touch.sh" ] && set_perm "$MODPATH/tools/probe_touch.sh" 0 0 0755

# webui/ is created lazily by app.js on first launch (mkdir -p before
# its first write), but creating it here too means the directory has
# the module's own uid/gid/context from the start rather than
# whatever app.js's shell context would give it.
mkdir -p "$MODPATH/webui" 2>/dev/null
set_perm_recursive "$MODPATH/webui" 0 0 0755 0644 2>/dev/null

banner
ui_print " Done. Reboot to apply, or use the WebUI / Action"
ui_print " button afterwards to re-apply without rebooting."
banner
