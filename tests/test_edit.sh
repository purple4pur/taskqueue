#!/usr/bin/env bash
# Tests for `tq edit`.
set -u
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
trap finish EXIT

setup_sandbox

set_queue '[ ] echo hi'
out=$( ( export EDITOR=cat; run_tq edit ) )
assert_contains "opens the queue with the configured editor" '[ ] echo hi' "$out"

unset EDITOR
run_tq edit >/dev/null 2>"$SANDBOX/err"
assert_eq "fails when EDITOR is unset" 1 "$?"
assert_file_contains "names the missing EDITOR variable" "EDITOR" "$SANDBOX/err"

rm -f "$QUEUE_FILE"
( export EDITOR=true; run_tq edit >/dev/null 2>&1 )
assert_eq "creates the queue before editing" "yes" "$([ -f "$QUEUE_FILE" ] && echo yes || echo no)"
