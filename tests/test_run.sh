#!/usr/bin/env bash
# Tests for the runner: success, failure, stderr capture, quoting, parallelism.
set -u
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
trap finish EXIT

setup_sandbox

set_queue
run_tq add 'echo hello' >/dev/null
run_runner >"$SANDBOX/out" 2>&1
assert_queue_count "records a successful task" '^\[x\] ' 1
assert_contains "prints the command before running it" 'echo hello' "$(cat "$SANDBOX/out")"
assert_contains "prints the success line" "Job finished successfully" "$(cat "$SANDBOX/out")"
if grep -Eq '^\[x\] .*\[[0-9]+s\]$' "$QUEUE_FILE"; then
    pass "records a non-empty elapsed time"
else
    fail "records a non-empty elapsed time" "$(cat "$QUEUE_FILE")"
fi

set_queue
run_tq add 'echo boom >&2; exit 3' >/dev/null
run_runner >/dev/null 2>&1
failure_line=$(cat "$QUEUE_FILE")
assert_contains "records the exit code" "[3:" "$failure_line"
log_path=$(printf '%s' "$failure_line" | sed -E 's/.*\[3:(.+\.log)\]$/\1/')
assert_eq "writes the stderr log" "yes" "$([ -f "$log_path" ] && echo yes || echo no)"
assert_eq "captures the whole stderr message" "boom" "$(cat "$log_path")"

set_queue
run_tq add 'seq 1 100000 >&2; exit 1' >/dev/null
run_runner >/dev/null 2>&1
big_log=$(printf '%s' "$(cat "$QUEUE_FILE")" | sed -E 's/.*\[1:(.+\.log)\]$/\1/')
assert_eq "keeps a large stderr log intact" "$(seq 1 100000 | wc -c)" "$(wc -c < "$big_log")"

set_queue
run_tq add "echo 'a#b & c' >> $SANDBOX/hits" >/dev/null
timeout 20 "$CLI" run >/dev/null 2>&1
assert_eq "terminates on a command containing a hash" 0 "$?"
assert_eq "runs such a task exactly once" 1 "$(wc -l < "$SANDBOX/hits")"
assert_queue_count "records such a task as successful" '^\[x\] ' 1

set_queue '[?] echo paused'
run_runner >/dev/null 2>&1
assert_line "leaves a paused task alone" 1 '[?] echo paused'
assert_queue_count "does not execute a paused task" '^\[x\] ' 0

set_queue '[ ]echo malformed' '[ ] echo good'
run_runner >/dev/null 2>&1
assert_line "leaves a malformed record alone" 1 '[ ]echo malformed'
assert_queue_count "executes the well-formed record" '^\[x\] ' 1

rm -f "$QUEUE_FILE"
out=$(run_runner 2>&1)
assert_contains "reports a missing queue file" "Tasks not found" "$out"

set_queue
run_tq add 'echo noisy >&2' >/dev/null
run_runner >/dev/null 2>"$SANDBOX/err"
assert_contains "replays task stderr" "noisy" "$(cat "$SANDBOX/err")"

set_queue
run_tq add 'echo early >&2; sleep 2; echo late >&2' >/dev/null
run_runner >"$SANDBOX/out" 2>"$SANDBOX/live.err" &
live_pid=$!
for _ in $(seq 1 50); do
    grep -q early "$SANDBOX/live.err" 2>/dev/null && break
    sleep 0.1
done
assert_file_contains "streams task stderr while it runs" "early" "$SANDBOX/live.err"
assert_not_contains "does not defer stderr until the task exits" "late" "$(cat "$SANDBOX/live.err")"
wait "$live_pid"
assert_file_contains "streams the tail before recording the result" "late" "$SANDBOX/live.err"

set_queue
run_tq add 'sleep 3 & echo done >&2' >/dev/null
out=$(run_runner 2>"$SANDBOX/daemon.err")
assert_eq "finishes when a child keeps stderr open" 0 "$?"
assert_contains "relays stderr before killing the relay" "done" "$(cat "$SANDBOX/daemon.err")"
assert_queue_count "records such a task as successful" '^\[x\] ' 1

set_queue
for i in $(seq 1 20); do
    run_tq add "echo t$i >> $SANDBOX/runs" >/dev/null
done
"$CLI" run >"$SANDBOX/r1" 2>&1 &
pid1=$!
"$CLI" run >"$SANDBOX/r2" 2>&1 &
pid2=$!
wait "$pid1"
wait "$pid2"
assert_eq "parallel runners execute every task" 20 "$(wc -l < "$SANDBOX/runs")"
assert_eq "parallel runners execute each task once" 20 "$(sort "$SANDBOX/runs" | uniq | wc -l)"
assert_queue_count "parallel runners record every task" '^\[x\] ' 20
assert_eq "parallel runners never time out on the lock" 0 "$(cat "$SANDBOX/r1" "$SANDBOX/r2" | grep -c '无法获取文件锁' || true)"

# Elapsed time must not depend on bc.
mkdir -p "$SANDBOX/bin"
for cmd in bash date awk sed grep cut mktemp mkfifo mv rm chmod dirname tr flock cat wc sort head tail ln seq tee sleep; do
    if command -v "$cmd" >/dev/null; then
        ln -sf "$(command -v "$cmd")" "$SANDBOX/bin/$cmd"
    fi
done
set_queue
( export PATH="$SANDBOX/bin"; "$CLI" add 'true' >/dev/null; "$CLI" run >/dev/null 2>&1 )
if grep -Eq '^\[x\] .*\[[0-9]+s\]$' "$QUEUE_FILE"; then
    pass "records elapsed time without bc on PATH"
else
    fail "records elapsed time without bc on PATH" "$(cat "$QUEUE_FILE")"
fi
