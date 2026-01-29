#!/usr/bin/env bash

# 配置文件路径
readonly JOBS_FILE="$HOME/opt/taskqueue/tasks.txt"
readonly RUNNER_SCRIPT="$HOME/opt/taskqueue/runner.sh"
readonly LOCK_FILE="$HOME/opt/taskqueue/.lock"

# 颜色定义
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# 安全引用字符串
safe_quote() {
    printf '%q' "$1"
}

# 获取文件锁
acquire_lock() {
    local timeout=10
    local lockfile="$1"

    exec 200>"$lockfile"

    for ((i=0; i<timeout; i++)); do
        if flock -n 200; then
            return 0
        fi
        sleep 1
    done

    echo -e "${RED}错误: 无法获取文件锁${NC}" >&2
    return 1
}

# 释放文件锁
release_lock() {
    flock -u 200
    exec 200>&-
}
