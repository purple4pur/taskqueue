#!/usr/bin/env bash
# Tests for `tq list` / `tq`.
set -u
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
trap finish EXIT

setup_sandbox

set_queue \
    '[ ] echo queued' \
    '[?] echo paused' \
    '[-] echo running [10/24 12:00] [R:123]' \
    '[x] echo done [10/24 12:00] [5s]' \
    '[!] false [10/24 12:00] [3s] [1:/q/.tq_err_L5_10241200.log]' \
    '[ ]broken'

out=$(run_tq list | plain)
assert_contains "labels the first queued task" "Q1 [ ] echo queued" "$out"
assert_contains "labels a paused task" "P1 [?] echo paused" "$out"
assert_contains "labels a running task" "RUN [-] echo running" "$out"
assert_contains "labels a successful task" "SUC [x] echo done" "$out"
assert_contains "labels a failed task" "FAI [!] false" "$out"
assert_contains "labels a malformed record" "UNK [ ]broken" "$out"

raw=$(run_tq list)
assert_contains "colors the start time" $'\033[0;35m[10/24 12:00]\033[0m' "$raw"
assert_contains "colors the runner tag" $'\033[1;33m[R:123]\033[0m' "$raw"
assert_contains "colors the elapsed time" $'\033[0;36m[5s]\033[0m' "$raw"
assert_contains "colors the error log pointer" $'\033[0;31m[1:/q/.tq_err_L5_10241200.log]\033[0m' "$raw"

set_queue '[ ] first' '[ ] second' '[?] paused'
out=$(run_tq list | plain)
assert_contains "numbers queued tasks in order" "Q2 [ ] second" "$out"

rm -f "$QUEUE_FILE"
out=$(run_tq list)
assert_contains "reports a missing queue" "任务文件不存在" "$out"

set_queue '[ ] A' '[x] B [01/01 00:00] [1s]'
list_out=$(run_tq list | plain | tail -n +4)
bare_out=$(run_tq | plain | tail -n +4)
assert_eq "bare tq behaves like list" "$list_out" "$bare_out"

for i in $(seq 1 1000); do
    echo "[x] echo task$i [10/24 12:00] [1s]"
done > "$QUEUE_FILE"
start_ns=$(date +%s%N)
run_tq list >/dev/null
elapsed_ms=$(( ($(date +%s%N) - start_ns) / 1000000 ))
if [ "$elapsed_ms" -lt 2000 ]; then
    pass "lists 1000 records in under 2s (${elapsed_ms}ms)"
else
    fail "lists 1000 records in under 2s" "took ${elapsed_ms}ms"
fi
