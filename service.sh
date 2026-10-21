#!/system/bin/sh
# Late-boot entrypoint. Kept intentionally thin — all the actual logic
# lives in apply.sh so the WebUI and action.sh can trigger it too
# without waiting on boot_completed again.

MODDIR=${0%/*}
LOGTAG="HyperTouch"

# Cap the wait: sys.boot_completed reaching 1 is the normal case, but
# if it never does (bootloop-adjacent state, some other module wedging
# boot), waiting forever means HyperTouch never gets a chance to run —
# or log anything — this boot. 10 minutes (200 * 3s) is generous but
# bounded.
i=0
max_wait=200
while [ "$(getprop sys.boot_completed)" != "1" ]; do
    i=$((i + 1))
    if [ "$i" -gt "$max_wait" ]; then
        log -p w -t "$LOGTAG" "service.sh: sys.boot_completed never reached 1 after ${max_wait}x3s — running apply.sh anyway."
        break
    fi
    sleep 3
done

# Small settle delay: on duchamp the touch/thermal/GPU drivers can take
# a moment after boot_completed before their sysfs nodes are writable.
sleep 5

sh "$MODDIR/apply.sh"
