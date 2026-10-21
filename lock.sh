#!/system/bin/sh
# Shared concurrency lock for HyperTouch. Sourced by apply.sh, action.sh,
# uninstall.sh and the WebUI's config writer so that settings.conf writes
# and apply/revert passes share one critical section.
#
# mkdir is atomic on POSIX filesystems, so acquisition itself can't race.
#
# v3.1.5: a lock whose owner is still ALIVE is never stolen any more. The
# old code force-removed it after ~8s, so a slow-but-legitimate operation
# could have the lock pulled out from under it and run concurrently with
# another one. Now: dead owner -> reclaim at once; live owner -> keep
# waiting (HT_LOCK_WAIT seconds, default 120) and then give up with an
# error instead of stealing.

_HT_LOCK="$MODDIR/.apply.lock"
_HT_LOCK_PIDFILE="$_HT_LOCK/pid"
HT_LOCK_WAIT=${HT_LOCK_WAIT:-120}

_ht_lock_reclaim() {
    # Rename first: only one competing waiter can win the rename.
    if mv "$_HT_LOCK" "$_HT_LOCK.stale.$$" 2>/dev/null; then
        rm -rf "$_HT_LOCK.stale.$$" 2>/dev/null
    fi
}

ht_lock_acquire() {
    _hl_i=0
    _hl_nopid=0
    while ! mkdir "$_HT_LOCK" 2>/dev/null; do
        _hl_i=$((_hl_i + 1))
        if [ "$_hl_i" -gt "$HT_LOCK_WAIT" ]; then
            echo "! HyperTouch: another operation (pid ${_hl_owner:-?}) still holds the lock after ${HT_LOCK_WAIT}s — not stealing it. Try again shortly."
            return 1
        fi
        _hl_owner=$(cat "$_HT_LOCK_PIDFILE" 2>/dev/null)
        if [ -n "$_hl_owner" ]; then
            if ! kill -0 "$_hl_owner" 2>/dev/null; then
                # Owner crashed / was killed without cleaning up.
                _ht_lock_reclaim
                continue
            fi
        else
            # No pidfile yet: owner may be between mkdir and writing it.
            _hl_nopid=$((_hl_nopid + 1))
            if [ "$_hl_nopid" -gt 3 ]; then
                _ht_lock_reclaim
                _hl_nopid=0
                continue
            fi
        fi
        sleep 1
    done
    echo $$ > "$_HT_LOCK_PIDFILE" 2>/dev/null
    trap 'ht_lock_release' EXIT
    trap 'ht_lock_release; exit 1' INT TERM
    return 0
}

# Only removes the lock if this process owns it.
ht_lock_release() {
    if [ "$(cat "$_HT_LOCK_PIDFILE" 2>/dev/null)" = "$$" ]; then
        rm -rf "$_HT_LOCK" 2>/dev/null
    fi
    trap - EXIT INT TERM
}
