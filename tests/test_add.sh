#!/usr/bin/env bash
# Tests for `tq add`.
set -u
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
trap finish EXIT

setup_sandbox

set_queue
run_tq add 'echo hello' >/dev/null
assert_line "records the working directory and command" 1 "[ ] cd $WORK_DIR && echo hello"

run_tq add echo "a  b" >/dev/null
assert_line "joins every argument into one command" 2 "[ ] cd $WORK_DIR && echo a  b"

if run_tq add >/dev/null 2>"$SANDBOX/err"; then
    fail "requires a command" "exit 0"
else
    pass "requires a command"
fi
assert_file_contains "prints usage on a missing command" "用法: tq add" "$SANDBOX/err"

line_count_before=$(wc -l < "$QUEUE_FILE")
run_tq add "$(printf 'echo a\necho b')" >/dev/null 2>&1
assert_eq "rejects an embedded newline" 1 "$?"
assert_eq "keeps one record per add" "$line_count_before" "$(wc -l < "$QUEUE_FILE")"

run_tq add "$(printf 'echo a\recho b')" >/dev/null 2>&1
assert_eq "rejects an embedded carriage return" 1 "$?"

run_tq add 'echo "a#b & c" | cat' >/dev/null
assert_file_contains "stores shell metacharacters verbatim" 'echo "a#b & c" | cat' "$QUEUE_FILE"

rm -f "$QUEUE_FILE"
run_tq add 'true' >/dev/null
assert_eq "creates a new queue with mode 600" 600 "$(stat -c %a "$QUEUE_FILE")"

mkdir -p "$SANDBOX/dir #1"
( cd "$SANDBOX/dir #1" && "$CLI" add 'pwd' >/dev/null )
assert_file_contains "quotes a directory containing a space and a hash" 'dir\ #1 && pwd' "$QUEUE_FILE"

set_queue '[x] old [01/01 00:00] [1s]'
run_tq add 'echo appended' >/dev/null
assert_queue_count "appends without touching earlier records" '^\[x\] old' 1
assert_line "appends at the end" 2 "[ ] cd $WORK_DIR && echo appended"
