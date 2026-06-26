#!/usr/bin/env bash

readonly TQ_DIR="$1"
source $HOME/opt/taskqueue/common.sh

# Derive the actual queue directory from JOBS_FILE (handles global mode where TQ_DIR is empty)
QUEUE_DIR=$(dirname "$JOBS_FILE")

while true; do
    if [ ! -f "$JOBS_FILE" ]; then
        echo -e "${YELLOW}[R:$$] Tasks not found.${NC}" >&2
        break
    fi

    # Acquire file lock
    if ! acquire_lock "$LOCK_FILE"; then
        return 1
    fi

    # Find the line number of the first un-executed job
    LINE_NUM=$(grep -n -m 1 "^\[ \]" "$JOBS_FILE" | cut -d: -f1)

    # Check if there are any un-executed jobs left
    if [ -z "$LINE_NUM" ]; then
        release_lock
        break
    fi

    # Extract the command and append this runner's PID
    JOB_LINE=$(sed -n "${LINE_NUM}p" "$JOBS_FILE")
    JOB_COMMAND=$(echo "$JOB_LINE" | sed -e 's#^\[ \] ##')
    SAFE_JOB_COMMAND=$(safe_quote "$JOB_COMMAND")
    START_DATE=$(date +%m/%d\ %H:%M)
    EXECUTING_JOB_LINE="[-] $SAFE_JOB_COMMAND [$START_DATE] [R:$$]"

    # Replace the line with the executing status
    sed -i "${LINE_NUM}s#.*#$EXECUTING_JOB_LINE#" "$JOBS_FILE"

    release_lock

    # Display runner command
    echo -e "${CYAN}[R:$$] $JOB_COMMAND${NC}"

    # Record start time
    START=$(date +%s.%N)

    # Capture stderr to a temp file
    STDERR_FILE=$(mktemp)

    # Execute the command, redirecting stderr to temp file
    bash -c "$JOB_COMMAND" 2> >(tee "$STDERR_FILE")
    STATUS=$?

    # Calculate elapsed time
    END=$(date +%s.%N)
    ELAPSED=$(echo "$END - $START" | bc | awk '
        {h=int($1/3600);m=int(($1%3600)/60);s=$1%60
         if(h) printf "%dh%dm%.0fs",h,m,s
         else if(m) printf "%dm%.0fs",m,s
         else printf "%.0fs",s}')

    # Acquire file lock
    if ! acquire_lock "$LOCK_FILE"; then
        return 1
    fi

    # Update the job status based on execution result
    if [ $STATUS -eq 0 ]; then
        # Update the job status to completed
        sed -i "/R:$$/s#.*#[x] $SAFE_JOB_COMMAND [$START_DATE] [$ELAPSED]#" "$JOBS_FILE"
        rm -f "$STDERR_FILE"
        echo -e "${GREEN}[R:$$] Job finished successfully. ${YELLOW}[$ELAPSED]${NC}"
    else
        # Write stderr log in-place
        STDERR_LOG="$QUEUE_DIR/.tq_err_L${LINE_NUM}_$(echo "$START_DATE" | tr -d ' /:').log"
        mv "$STDERR_FILE" "$STDERR_LOG"
        # Update the job status to failed with error log info
        sed -i "/R:$$/s#.*#[!] $SAFE_JOB_COMMAND [$START_DATE] [$ELAPSED] [$STATUS:$STDERR_LOG]#" "$JOBS_FILE"
        echo -e "${RED}[R:$$] Job finished with code $STATUS. ${YELLOW}[$ELAPSED]${NC}" >&2
        echo -e "${RED}[R:$$] stderr log: $STDERR_LOG${NC}" >&2
    fi

    release_lock
done

echo -e "${CYAN}[R:$$] All jobs are completed.${NC}"
