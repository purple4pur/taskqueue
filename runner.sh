#!/usr/bin/env bash

source $HOME/opt/taskqueue/common.sh

while true; do
    if ! acquire_lock "$LOCK_FILE"; then
        return 1
    fi

    # Find the line number of the first un-executed job
    LINE_NUM=$(grep -n -m 1 "^\[ \]" "$JOBS_FILE" | cut -d: -f1)

    # Check if there are any un-executed jobs left
    if [ -z "$LINE_NUM" ]; then
        break
    fi

    # Extract the command and append this runner's PID
    JOB_LINE=$(sed -n "${LINE_NUM}p" "$JOBS_FILE")
    JOB_COMMAND=$(echo "$JOB_LINE" | sed -e 's#^\[ \] ##')
    SAFE_JOB_COMMAND=$(safe_quote "$JOB_COMMAND")
    START_DATE=$(date +%m/%d\ %H:%M)
    EXECUTING_JOB_LINE="[-] $SAFE_JOB_COMMAND [$START_DATE] [$$]"

    # Replace the line with the executing status
    sed -i "${LINE_NUM}s#.*#$EXECUTING_JOB_LINE#" "$JOBS_FILE"

    release_lock

    echo -e "${CYAN}[Runner:$$] $JOB_COMMAND${NC}"

    # Record start time
    START=$(date +%s.%N)

    # Execute the command
    bash -c "$JOB_COMMAND"
    STATUS=$?

    # Calculate elapsed time
    END=$(date +%s.%N)
    ELAPSED=$(echo "$END - $START" | bc)
    HOURS=$(echo "$ELAPSED/3600" | bc)
    MINUTES=$(echo "($ELAPSED%3600)/60" | bc)
    SECONDS=$(echo "$ELAPSED%60" | bc | awk '{printf "%.0f", $1}')
    if [ $HOURS -gt 0 ]; then
        ELAPSED="${HOURS}h${MINUTES}m${SECONDS}s"
    elif [ $MINUTES -gt 0 ]; then
        ELAPSED="${MINUTES}m${SECONDS}s"
    else
        ELAPSED="${SECONDS}s"
    fi

    # Update the job status based on execution result
    if [ $STATUS -eq 0 ]; then
        # Update the job status to completed
        sed -i "/$$/s#.*#[x] $SAFE_JOB_COMMAND [$START_DATE] [$ELAPSED]#" "$JOBS_FILE"
        echo -e "${GREEN}[Runner:$$] Job finished successfully.${NC}"
    else
        # Update the job status to failed
        sed -i "/$$/s#.*#[!] $SAFE_JOB_COMMAND [$START_DATE] [$ELAPSED]#" "$JOBS_FILE"
        echo -e "${RED}[Runner:$$] Job finished with code $STATUS.${NC}"
    fi
done

echo -e "${CYAN}[Runner:$$] All jobs are completed.${NC}"
