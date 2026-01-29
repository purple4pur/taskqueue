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
    EXECUTING_JOB_LINE="[-] $SAFE_JOB_COMMAND [$$]"

    # Replace the line with the executing status
    sed -i "${LINE_NUM}s#.*#$EXECUTING_JOB_LINE#" "$JOBS_FILE"

    release_lock

    # Execute the command
    eval "$JOB_COMMAND"
    STATUS=$?

    # Update the job status based on execution result
    if [ $STATUS -eq 0 ]; then
        # Update the job status to completed
        sed -i "/$$/s#.*#[x] $SAFE_JOB_COMMAND#" "$JOBS_FILE"
    else
        # Update the job status to failed
        sed -i "/$$/s#.*#[!] $SAFE_JOB_COMMAND#" "$JOBS_FILE"
    fi
done

echo "All jobs are completed."
