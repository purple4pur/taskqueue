#!/usr/bin/env bash
# Tests for top, pause, resume, pauseall, resumeall, clean, cleanall, reset, rerun.
set -u
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
trap finish EXIT

setup_sandbox

set_queue \
    '[x] old [01/01 00:00] [1s]' \
    '[ ] A' \
    '[?] B' \
    '[ ] C' \
    '[-] D [01/01 00:00] [R:99]' \
    '[ ] E'

run_tq pause 2 >/dev/null
assert_line "pause marks the Nth queued task" 4 '[?] C'

run_tq resume 1 >/dev/null
assert_line "resume marks the Nth paused task" 3 '[ ] B'

run_tq top 3 >/dev/null
assert_line "top moves the Nth queued task to the front" 2 '[ ] E'
assert_line "top keeps the remaining order" 3 '[ ] A'
assert_line "top leaves the paused task in place" 5 '[?] C'
assert_line "top leaves the running task alone" 6 '[-] D [01/01 00:00] [R:99]'

cp "$QUEUE_FILE" "$SANDBOX/before"
run_tq pause 9 >/dev/null 2>&1
assert_eq "pause rejects an out-of-range index" 1 "$?"
run_tq top 9 >/dev/null 2>&1
assert_eq "top rejects an out-of-range index" 1 "$?"
run_tq resume 9 >/dev/null 2>&1
assert_eq "resume rejects an out-of-range index" 1 "$?"
assert_eq "failed index commands leave the queue unchanged" "" "$(diff "$SANDBOX/before" "$QUEUE_FILE")"

for subcommand in top pause resume; do
    run_tq "$subcommand" abc >/dev/null 2>&1
    assert_eq "$subcommand rejects a non-numeric index" 1 "$?"
    run_tq "$subcommand" 0 >/dev/null 2>&1
    assert_eq "$subcommand rejects zero" 1 "$?"
done

set_queue '[ ] A' '[?] B' '[x] C [01/01 00:00] [1s]'
run_tq pauseall >/dev/null
assert_queue_count "pauseall pauses every queued task" '^\[\?\] ' 2
run_tq resumeall >/dev/null
assert_queue_count "resumeall requeues every paused task" '^\[ \] ' 2

set_queue \
    '[ ] A' \
    '[x] B [01/01 00:00] [1s]' \
    '[!] C [01/01 00:00] [2s] [1:/q/x.log]' \
    '[?] D' \
    '[-] E [01/01 00:00] [R:1]'
out=$(run_tq clean)
assert_contains "clean reports two removed tasks" "已移除: 2" "$out"
assert_queue_count "clean keeps queued tasks" '^\[ \] ' 1
assert_queue_count "clean keeps paused tasks" '^\[\?\] ' 1
assert_queue_count "clean keeps running tasks" '^\[-\] ' 1

printf '[x] a [01/01 00:00] [1s]\n[x] b' > "$QUEUE_FILE"
out=$(run_tq clean)
assert_contains "clean counts an unterminated last record" "已移除: 2" "$out"
assert_eq "clean empties the queue" 0 "$(grep -c . "$QUEUE_FILE" || true)"

set_queue '[ ] A' '[?] B' '[x] C [01/01 00:00] [1s]' '[-] D [01/01 00:00] [R:1]'
run_tq cleanall >/dev/null
assert_eq "cleanall keeps only the running record" 1 "$(grep -c . "$QUEUE_FILE")"
assert_queue_count "cleanall keeps the running record" '^\[-\] ' 1

set_queue \
    '[x] echo done [01/01 00:00] [1s]' \
    '[!] false [01/01 00:00] [3s] [1:/q/.tq_err_L2_01010000.log]' \
    '[x] echo noelapsed [01/01 00:00] []' \
    '[?] echo paused' \
    '[ ] echo queued [01/01 00:00] [1s]' \
    '[-] echo running [01/01 00:00] [R:1]'
run_tq reset >/dev/null
assert_line "reset strips the elapsed field" 1 '[ ] echo done'
assert_line "reset strips the log pointer" 2 '[ ] false'
assert_line "reset strips an empty elapsed field" 3 '[ ] echo noelapsed'
assert_line "reset requeues a paused task" 4 '[ ] echo paused'
assert_line "reset leaves a queued command untouched" 5 '[ ] echo queued [01/01 00:00] [1s]'
assert_line "reset leaves the running task alone" 6 '[-] echo running [01/01 00:00] [R:1]'

reset_once=$(cat "$QUEUE_FILE")
run_tq reset >/dev/null
assert_eq "reset is idempotent" "$reset_once" "$(cat "$QUEUE_FILE")"

printf '%s\n' '[ ] echo first' '[ ] echo AA\tBB' > "$QUEUE_FILE"
chmod 640 "$QUEUE_FILE"
run_tq top 2 >/dev/null
assert_line "top keeps backslash escapes byte-exact" 1 '[ ] echo AA\tBB'
assert_eq "top keeps the queue file mode" 640 "$(stat -c %a "$QUEUE_FILE")"

set_queue "[x] echo rerun >> $SANDBOX/hits [01/01 00:00] [1s]"
run_tq rerun >/dev/null 2>&1
assert_eq "rerun executes the reset task" 1 "$(wc -l < "$SANDBOX/hits")"
assert_queue_count "rerun records the task again" '^\[x\] ' 1
