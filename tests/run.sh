#!/usr/bin/env bash
# Run every test file and summarize the results.
set -u

cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1
TQ_REPO=$(cd .. && pwd)
export TQ_REPO

total_pass=0
total_fail=0
failed_files=0

for test_file in test_*.sh; do
    printf '\n=== %s ===\n' "$test_file"

    output=$(bash "$test_file" 2>&1)
    status=$?
    printf '%s\n' "$output"

    summary=$(printf '%s\n' "$output" | grep '^RESULT ' | tail -1)
    pass_n=$(printf '%s' "$summary" | sed -E 's/.*pass=([0-9]+).*/\1/')
    fail_n=$(printf '%s' "$summary" | sed -E 's/.*fail=([0-9]+).*/\1/')

    case "$pass_n" in
        ''|*[!0-9]*) pass_n=0 ;;
    esac
    case "$fail_n" in
        ''|*[!0-9]*) fail_n=1 ;;
    esac

    total_pass=$((total_pass + pass_n))
    total_fail=$((total_fail + fail_n))
    if [ "$status" -ne 0 ]; then
        failed_files=$((failed_files + 1))
    fi
done

printf '\nTOTAL pass=%d fail=%d failed_files=%d\n' "$total_pass" "$total_fail" "$failed_files"
[ "$total_fail" -eq 0 ]
