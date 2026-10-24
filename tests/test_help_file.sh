#!/usr/bin/env bash
# Tests for `tq help`, `tq file`, and unknown subcommands.
set -u
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
trap finish EXIT

setup_sandbox

out=$(run_tq help)
assert_eq "help exits zero" 0 "$?"
for expected in "tq add" "tq run" "tq top" "tq pause" "tq pauseall" "tq resume" "tq resumeall" "tq clean" "tq cleanall" "tq reset" "tq rerun" "tq file" "tq edit" "tq help" "tq local"; do
    assert_contains "help documents $expected" "$expected" "$out"
done

out=$(run_tq file)
assert_eq "file prints the queue path" "$QUEUE_FILE" "$out"

run_tq nope >/dev/null 2>"$SANDBOX/err"
assert_eq "unknown subcommand fails" 1 "$?"
assert_file_contains "unknown subcommand explains itself" "未知命令" "$SANDBOX/err"
