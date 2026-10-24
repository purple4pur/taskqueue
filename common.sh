#!/usr/bin/env bash

# Keep the queue, lock, and logs private to the current user
umask 077

# Paths and configuration
readonly BASE_DIR="$HOME/opt/taskqueue"
readonly RUNNER_SCRIPT="$BASE_DIR/runner.sh"
readonly JOBS_FILE="${TQ_DIR:-$BASE_DIR}/tasks.txt"
readonly LOCK_FILE="${TQ_DIR:-$BASE_DIR}/.lock"

# ANSI colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly GRAY='\033[0;90m'
readonly NC='\033[0m' # No Color

# Acquire the queue lock
acquire_lock() {
    local lockfile="$1"

    # Open in append mode so a symlinked lock target is never truncated
    if ! exec 200>>"$lockfile"; then
        echo -e "${RED}错误: 无法打开锁文件 $lockfile${NC}" >&2
        return 1
    fi

    # Let flock own the wait instead of polling in whole seconds
    if flock -w 10 200; then
        return 0
    fi

    echo -e "${RED}错误: 无法获取文件锁${NC}" >&2
    return 1
}

# Release the queue lock
release_lock() {
    flock -u 200
    exec 200>&-
}

# Replace one queue line by exact full-line match
# Task text travels as data, so punctuation such as # & \ cannot alter the record
queue_replace_line() {
    local old_line="$1"
    local new_line="$2"
    local temp_file

    temp_file=$(mktemp "$(dirname "$JOBS_FILE")/.tasks.XXXXXX") || return 1

    # Compare whole lines in awk; the replacement text arrives through the environment
    if ! OLD_LINE="$old_line" NEW_LINE="$new_line" awk '
        BEGIN { old = ENVIRON["OLD_LINE"]; new = ENVIRON["NEW_LINE"] }
        $0 == old { print new; found = 1; next }
        { print }
        END { exit(found ? 0 : 1) }
    ' "$JOBS_FILE" > "$temp_file"; then
        rm -f "$temp_file"
        return 1
    fi

    chmod --reference="$JOBS_FILE" "$temp_file"
    mv "$temp_file" "$JOBS_FILE"
}
