#!/usr/bin/env bash
# Tests for install.sh.
set -u
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
trap finish EXIT

setup_sandbox

for script in taskqueue.sh runner.sh common.sh; do
    if [ -x "$HOME/opt/taskqueue/$script" ]; then
        pass "installs $script executable"
    else
        fail "installs $script executable" "missing or not executable"
    fi
done

assert_eq "installs a private queue file" 600 "$(stat -c %a "$QUEUE_FILE")"
assert_file_contains "prints the tql alias" 'alias tql="tq local"' "$SANDBOX/install.log"
assert_not_contains "never redefines the tq alias" 'alias tq="tq local"' "$(cat "$SANDBOX/install.log")"

set_queue '[ ] keep me'
( cd "$TQ_REPO" && bash ./install.sh >"$SANDBOX/reinstall.log" 2>&1 )
assert_eq "reinstall keeps the queue" 0 "$?"
assert_line "reinstall preserves existing records" 1 '[ ] keep me'
