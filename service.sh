#!/system/bin/sh
# Late-boot entrypoint. Kept intentionally thin — all the actual logic
# lives in apply.sh so the WebUI and action.sh can trigger it too
# without waiting on boot_completed again.

MODDIR=${0%/*}

while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 3
done

# Small settle delay: on duchamp the touch/thermal/GPU drivers can take
# a moment after boot_completed before their sysfs nodes are writable.
sleep 5

sh "$MODDIR/apply.sh"
