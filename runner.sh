#!/usr/bin/env bash

readonly TQ_DIR="$1"
source "$HOME/opt/taskqueue/common.sh"

# Derive the actual queue directory from JOBS_FILE (handles global mode where TQ_DIR is empty)
QUEUE_DIR=$(dirname "$JOBS_FILE")

# Drop the stderr relay even when the runner is interrupted mid-task
cleanup_stderr_relay() {
    [ -n "${TEE_PID:-}" ] && kill "$TEE_PID" 2>/dev/null
    [ -n "${STDERR_DIR:-}" ] && rm -rf "$STDERR_DIR"
}
trap cleanup_stderr_relay EXIT

while true; do
    if [ ! -f "$JOBS_FILE" ]; then
        echo -e "${YELLOW}[R:$$] Tasks not found.${NC}" >&2
        break
    fi

    # Acquire file lock
    if ! acquire_lock "$LOCK_FILE"; then
        exit 1
    fi

    # Find the line number of the first un-executed job
    LINE_NUM=$(grep -n -m 1 "^\[ \] " "$JOBS_FILE" | cut -d: -f1)

    # Check if there are any un-executed jobs left
    if [ -z "$LINE_NUM" ]; then
        release_lock
        break
    fi

    # Extract the command and append this runner's PID
    JOB_LINE=$(sed -n "${LINE_NUM}p" "$JOBS_FILE")
    JOB_COMMAND="${JOB_LINE#\[ \] }"
    START_DATE=$(date +%m/%d\ %H:%M)
    EXECUTING_JOB_LINE="[-] $JOB_COMMAND [$START_DATE] [R:$$]"

    # Mark the record as running without routing task text through sed or awk
    if ! queue_replace_line "$JOB_LINE" "$EXECUTING_JOB_LINE"; then
        echo -e "${RED}[R:$$] Failed to mark task as running.${NC}" >&2
        release_lock
        exit 1
    fi

    release_lock

    # Display runner command
    echo -e "${CYAN}[R:$$] $JOB_COMMAND${NC}"

    # Record start time
    START=$(date +%s.%N)

    # Relay stderr to the terminal while keeping a copy for the failure log
    STDERR_FILE=$(mktemp)
    STDERR_DIR=$(mktemp -d)
    mkfifo "$STDERR_DIR/fifo"
    tee "$STDERR_FILE" <"$STDERR_DIR/fifo" >&2 &
    TEE_PID=$!

    bash -c "$JOB_COMMAND" 2>"$STDERR_DIR/fifo"
    STATUS=$?

    # Drain the relay so the log is complete before recording the result, but cap
    # the wait: a task that leaves a child holding stderr open must not stall us
    ( sleep 2; kill "$TEE_PID" 2>/dev/null ) &
    WATCHDOG_PID=$!
    wait "$TEE_PID" 2>/dev/null
    kill "$WATCHDOG_PID" 2>/dev/null
    wait "$WATCHDOG_PID" 2>/dev/null
    rm -rf "$STDERR_DIR"
    STDERR_DIR=

    # Calculate elapsed time
    END=$(date +%s.%N)
    ELAPSED=$(awk -v start="$START" -v end="$END" 'BEGIN {
        elapsed = end - start
        h = int(elapsed / 3600)
        m = int((elapsed % 3600) / 60)
        s = int(elapsed % 60)
        if (h) printf "%dh%dm%ds", h, m, s
        else if (m) printf "%dm%ds", m, s
        else printf "%ds", s
    }')

    # Acquire file lock
    if ! acquire_lock "$LOCK_FILE"; then
        exit 1
    fi

    # Update the job status based on execution result
    if [ $STATUS -eq 0 ]; then
        # Locate the running record by its exact text, never by a PID substring
        queue_replace_line "$EXECUTING_JOB_LINE" "[x] $JOB_COMMAND [$START_DATE] [$ELAPSED]" ||
            echo -e "${RED}[R:$$] Failed to record result.${NC}" >&2
        rm -f "$STDERR_FILE"
        echo -e "${GREEN}[R:$$] Job finished successfully. ${YELLOW}[$ELAPSED]${NC}"
    else
        # Write stderr log in-place
        STDERR_LOG="$QUEUE_DIR/.tq_err_L${LINE_NUM}_$(echo "$START_DATE" | tr -d ' /:').log"
        mv "$STDERR_FILE" "$STDERR_LOG"
        # Update the job status to failed with error log info
        queue_replace_line "$EXECUTING_JOB_LINE" "[!] $JOB_COMMAND [$START_DATE] [$ELAPSED] [$STATUS:$STDERR_LOG]" ||
            echo -e "${RED}[R:$$] Failed to record result.${NC}" >&2
        echo -e "${RED}[R:$$] Job finished with code $STATUS. ${YELLOW}[$ELAPSED]${NC}" >&2
        echo -e "${RED}[R:$$] stderr log: $STDERR_LOG${NC}" >&2
    fi

    release_lock
done

echo -e "${CYAN}[R:$$] All jobs are completed.${NC}"
