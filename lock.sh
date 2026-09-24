#!/system/bin/sh
# Shared concurrency lock for HyperTouch. Sourced by both apply.sh and
# action.sh so that settings.conf writes (enable/disable/reset from
# action.sh or the WebUI) and apply.sh's read-and-apply pass share one
# critical section — not two separate ones. Previously action.sh wrote
# settings.conf *before* calling apply.sh, outside apply.sh's own
# lock, so a second process could read settings.conf mid-write, or two
# writers could interleave. Acquiring here, before either config
# mutation or apply, closes that gap.
#
# mkdir is atomic on POSIX filesystems, so lock acquisition itself
# can't race.

_HT_LOCK="$MODDIR/.apply.lock"
_HT_LOCK_PIDFILE="$_HT_LOCK/pid"

ht_lock_acquire() {
    i=0
    while ! mkdir "$_HT_LOCK" 2>/dev/null; do
        # Stale-lock check: if the PID that holds the lock is no
        # longer running, it crashed/was killed without cleaning up —
        # safe to reclaim immediately rather than waiting out the full
        # timeout. `kill -0` just tests existence, doesn't signal.
        if [ -f "$_HT_LOCK_PIDFILE" ]; then
            owner_pid=$(cat "$_HT_LOCK_PIDFILE" 2>/dev/null)
            if [ -n "$owner_pid" ] && ! kill -0 "$owner_pid" 2>/dev/null; then
                rm -rf "$_HT_LOCK" 2>/dev/null
                continue
            fi
        fi
        i=$((i + 1))
        if [ "$i" -gt 8 ]; then
            # Owner process still alive but taking a long time (or the
            # pidfile itself never got written) — clear it anyway
            # rather than hang forever; this is the same fallback the
            # original lock had.
            rm -rf "$_HT_LOCK" 2>/dev/null
            break
        fi
        sleep 1
    done
    mkdir "$_HT_LOCK" 2>/dev/null
    echo $$ > "$_HT_LOCK_PIDFILE" 2>/dev/null
    trap 'rm -rf "$_HT_LOCK" 2>/dev/null' EXIT INT TERM
}

ht_lock_release() {
    rm -rf "$_HT_LOCK" 2>/dev/null
    trap - EXIT INT TERM
}
