#!/usr/bin/env bash
# Tests for lock contention and lock failures.
set -u
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
trap finish EXIT

setup_sandbox

set_queue
for i in $(seq 1 20); do
    run_tq add "echo c$i" >/dev/null &
done
wait
assert_queue_count "concurrent adds keep every record" '^\[ \] ' 20

( flock -x "$HOME/opt/taskqueue/.lock" sleep 12 ) &
holder=$!
sleep 0.3
start_s=$(date +%s)
run_tq pause 1 >/dev/null 2>"$SANDBOX/lock.err"
lock_rc=$?
elapsed_s=$(( $(date +%s) - start_s ))
kill "$holder" 2>/dev/null
wait "$holder" 2>/dev/null

assert_eq "a busy lock returns a failure" 1 "$lock_rc"
assert_file_contains "a busy lock explains itself" "无法获取文件锁" "$SANDBOX/lock.err"
if [ "$elapsed_s" -ge 9 ]; then
    pass "a busy lock waits about ten seconds (${elapsed_s}s)"
else
    fail "a busy lock waits about ten seconds" "gave up after ${elapsed_s}s"
fi

chmod 555 "$HOME/opt/taskqueue"
run_tq rerun >/dev/null 2>&1
assert_eq "rerun aborts when reset cannot take the lock" 1 "$?"
chmod 755 "$HOME/opt/taskqueue"
