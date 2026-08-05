#!/system/bin/sh
# Runs when you tap "Action" for this module in the KernelSU/Magisk
# manager. Re-applies current settings.conf immediately, no reboot.

MODDIR=${0%/*}
echo "HyperTouch: re-applying settings..."
sh "$MODDIR/apply.sh"
echo "HyperTouch: done."
