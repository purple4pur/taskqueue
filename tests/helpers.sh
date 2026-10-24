#!/usr/bin/env bash
# Shared sandbox, assertions, and CLI helpers for the TaskQueue suite.

TQ_REPO=${TQ_REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}

PASS_COUNT=0
FAIL_COUNT=0
SANDBOX=
CLI=
RUNNER_SCRIPT=
QUEUE_FILE=
WORK_DIR=

# Create a throwaway HOME, install the scripts there, and enter a work directory.
setup_sandbox() {
    SANDBOX=$(mktemp -d)
    export HOME="$SANDBOX/home"
    mkdir -p "$HOME" "$SANDBOX/work"

    if ! ( cd "$TQ_REPO" && bash ./install.sh >"$SANDBOX/install.log" 2>&1 ); then
        printf 'FAIL install.sh exited non-zero\n'
        printf 'RESULT %s pass=0 fail=1\n' "${0##*/}"
        exit 1
    fi

    CLI="$HOME/opt/taskqueue/taskqueue.sh"
    RUNNER_SCRIPT="$HOME/opt/taskqueue/runner.sh"
    QUEUE_FILE="$HOME/opt/taskqueue/tasks.txt"
    WORK_DIR="$SANDBOX/work"
    cd "$WORK_DIR" || exit 1
}

teardown_sandbox() {
    cd /
    if [ -n "$SANDBOX" ]; then
        rm -rf "$SANDBOX"
    fi
    SANDBOX=
}

pass() {
    PASS_COUNT=$((PASS_COUNT + 1))
    printf 'PASS %s\n' "$1"
}

fail() {
    FAIL_COUNT=$((FAIL_COUNT + 1))
    printf 'FAIL %s — %s\n' "$1" "$2"
}

assert_eq() { # name expected actual
    if [ "$2" = "$3" ]; then
        pass "$1"
    else
        fail "$1" "expected [$2], got [$3]"
    fi
}

assert_ne() { # name unexpected actual
    if [ "$2" != "$3" ]; then
        pass "$1"
    else
        fail "$1" "did not expect [$2]"
    fi
}

assert_contains() { # name needle haystack
    case "$3" in
        *"$2"*) pass "$1" ;;
        *) fail "$1" "missing [$2] in [$3]" ;;
    esac
}

assert_not_contains() { # name needle haystack
    case "$3" in
        *"$2"*) fail "$1" "unexpected [$2]" ;;
        *) pass "$1" ;;
    esac
}

assert_line() { # name line-number expected
    assert_eq "$1" "$3" "$(sed -n "${2}p" "$QUEUE_FILE")"
}

assert_queue_count() { # name pattern expected (extended regex)
    local actual
    actual=$(grep -Ec -- "$2" "$QUEUE_FILE" 2>/dev/null || true)
    assert_eq "$1" "$3" "$actual"
}

assert_file_contains() { # name needle file
    if grep -qF -- "$2" "$3" 2>/dev/null; then
        pass "$1"
    else
        fail "$1" "missing [$2] in $3"
    fi
}

# Replace the queue with the given records, one per argument.
set_queue() {
    : > "$QUEUE_FILE"
    if [ "$#" -gt 0 ]; then
        printf '%s\n' "$@" >> "$QUEUE_FILE"
    fi
}

run_tq() {
    "$CLI" "$@"
}

# Run the queue to completion with a hard timeout so a regression cannot hang CI.
run_runner() {
    timeout 20 "$CLI" run
}

# Strip ANSI escapes so assertions can compare plain text.
plain() {
    sed -E 's/\x1b\[[0-9;]*m//g'
}

finish() {
    teardown_sandbox
    printf 'RESULT %s pass=%d fail=%d\n' "${0##*/}" "$PASS_COUNT" "$FAIL_COUNT"
    if [ "$FAIL_COUNT" -ne 0 ]; then
        exit 1
    fi
    exit 0
}
