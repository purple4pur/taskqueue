#!/usr/bin/env bash
# Tests for `tq local`.
set -u
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
trap finish EXIT

setup_sandbox

mkdir -p "$SANDBOX/project"
set_queue

( cd "$SANDBOX/project" && "$CLI" local file > "$SANDBOX/file.out" )
assert_eq "local file prints the local queue path" "$SANDBOX/project/tasks.txt" "$(cat "$SANDBOX/file.out")"

( cd "$SANDBOX/project" && "$CLI" local add 'echo local' >/dev/null )
assert_file_contains "local add writes the local queue" 'echo local' "$SANDBOX/project/tasks.txt"
assert_queue_count "local add leaves the global queue alone" '^\[ \] ' 0

( cd "$SANDBOX/project" && "$CLI" local run >/dev/null 2>&1 )
assert_file_contains "local run records success locally" '[x] cd' "$SANDBOX/project/tasks.txt"
assert_queue_count "local run leaves the global queue alone" '^\[x\] ' 0

mkdir -p "$SANDBOX/repo"
printf 'victim\n' > "$SANDBOX/victim"
ln -s "$SANDBOX/victim" "$SANDBOX/repo/.lock"
( cd "$SANDBOX/repo" && "$CLI" local add 'true' >/dev/null )
assert_eq "a symlinked lock target is not truncated" "victim" "$(cat "$SANDBOX/victim")"
assert_eq "a local queue is created private" 600 "$(stat -c %a "$SANDBOX/repo/tasks.txt")"
