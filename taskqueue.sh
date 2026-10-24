#!/usr/bin/env bash

# tq_list - show every task with its status {{{
tq_list() {
    echo -e "${CYAN}=== 任务队列状态 ($(date '+%Y-%m-%d %H:%M:%S')) ===${NC}"
    echo -e "${GREEN}文件: $JOBS_FILE${NC}"
    echo ""

    if [ ! -f "$JOBS_FILE" ]; then
        echo -e "${YELLOW}任务文件不存在或为空${NC}"
        return 0
    fi

    # Walk the queue and render one row per record
    local queue_order=1
    local paused_order=1
    while IFS= read -r line || [ -n "$line" ]; do
        local status="未知"

        # Classify the record by its status prefix
        if [[ "$line" == "[ ] "* ]]; then
            printf -v status "${CYAN}%3s${NC}" "Q$queue_order"
            ((queue_order++))
        elif [[ "$line" == "[?] "* ]]; then
            printf -v status "${MAGENTA}%3s${NC}" "P$paused_order"
            ((paused_order++))
        elif [[ "$line" =~ ^\[-\] ]]; then
            status="${YELLOW}RUN${NC}"
        elif [[ "$line" =~ ^\[x\] ]]; then
            status="${GREEN}SUC${NC}"
        elif [[ "$line" =~ ^\[\!\] ]]; then
            status="${RED}FAI${NC}"
        else
            status="${GRAY}UNK${NC}"
        fi

        # Print the row
        echo -e "$status $line"
    done < <(sed -E \
        -e "s#(\\[[0-9/]{5} [0-9:]{5}\\]) (\\[R:[0-9]+\\])#\\${MAGENTA}\\1\\${NC} \\${YELLOW}\\2\\${NC}#" \
        -e "s#(\\[[0-9/]{5} [0-9:]{5}\\]) (\\[[0-9hm]+s\\])#\\${MAGENTA}\\1\\${NC} \\${CYAN}\\2\\${NC}#" \
        -e "s#\\[([0-9]+):(.+\.log)\\]\$#\\${RED}[\\1:\\2]\\${NC}#" \
        "$JOBS_FILE")
}
#}}}

# tq_add - append a task to the queue {{{
tq_add() {
    if [ $# -eq 0 ]; then
        echo -e "${RED}错误: 请提供要运行的命令${NC}" >&2
        echo "用法: tq add <命令>" >&2
        return 1
    fi

    local current_dir
    current_dir=$(pwd)

    local command="$*"

    # The queue stores one record per line, so reject embedded newlines
    if [[ "$command" == *$'\n'* || "$command" == *$'\r'* ]]; then
        echo -e "${RED}错误: 命令不能包含换行符${NC}" >&2
        return 1
    fi

    # Prefix the command with the directory it was added from
    local safe_dir
    safe_dir=$(printf '%q' "$current_dir")

    local full_command="cd $safe_dir && $command"

    # Take the queue lock so concurrent writers cannot interleave
    if ! acquire_lock "$LOCK_FILE"; then
        return 1
    fi

    # Append one complete record
    echo "[ ] $full_command" >> "$JOBS_FILE" || {
        echo -e "${RED}错误: 无法写入任务文件${NC}" >&2
        release_lock
        return 1
    }

    release_lock

    echo -e "${GREEN}✓ 任务已添加到队列${NC}"
    echo -e "   目录: $current_dir"
    echo -e "   命令: $command"
}
#}}}

# tq_run - start one runner {{{
tq_run() {
    local tq_dir="$1"
    bash "$RUNNER_SCRIPT" "$tq_dir"
}
#}}}

# tq_top - move the Nth queued task to the front {{{
tq_top() {
    local n="$1"

    # Validate the argument
    if [ -z "$n" ]; then
        echo -e "${RED}错误: 请指定任务编号${NC}" >&2
        echo "用法: tq top <任务编号>" >&2
        return 1
    fi

    if ! [[ "$n" =~ ^[0-9]+$ ]] || [ "$n" -le 0 ]; then
        echo -e "${RED}错误: 任务编号必须是正整数${NC}" >&2
        return 1
    fi

    echo -e "${CYAN}正在将第 $n 个等待任务提前到第一位...${NC}"

    if [ ! -f "$JOBS_FILE" ]; then
        echo -e "${YELLOW}任务文件不存在${NC}"
        return 0
    fi

    if ! acquire_lock "$LOCK_FILE"; then
        return 1
    fi

    # Find the Nth waiting task line number
    local line_num target_line first_waiting waiting_count temp_file
    waiting_count=$(grep -c '^\[ \] ' "$JOBS_FILE")

    if [ "$n" -gt "$waiting_count" ]; then
        echo -e "${RED}错误: 只有 $waiting_count 个等待任务，无法移动第 $n 个${NC}" >&2
        release_lock
        return 1
    fi

    line_num=$(grep -n '^\[ \] ' "$JOBS_FILE" | sed -n "${n}{p;q}" | cut -d: -f1)
    first_waiting=$(grep -n '^\[ \] ' "$JOBS_FILE" | head -1 | cut -d: -f1)

    # Already first — nothing to do
    if [ "$line_num" = "$first_waiting" ]; then
        release_lock
        echo -e "${GREEN}✓ 第 $n 个等待任务已在第一位${NC}"
        echo ""
        tq_list
        return 0
    fi

    target_line=$(sed -n "${line_num}p" "$JOBS_FILE")

    # Keep the scratch file beside the queue so mv replaces it atomically
    temp_file=$(mktemp "$(dirname "$JOBS_FILE")/.tasks.XXXXXX") || {
        echo -e "${RED}错误: 无法创建临时文件${NC}" >&2
        release_lock
        return 1
    }

    # Remove Nth waiting task, insert before the first waiting task
    # Pass the stored line through the environment so awk keeps escapes literal
    if ! TARGET_LINE="$target_line" awk -v skip="$line_num" -v ins="$first_waiting" '
NR == ins { print ENVIRON["TARGET_LINE"] }
NR != skip { print }
' "$JOBS_FILE" > "$temp_file"; then
        rm -f "$temp_file"
        echo -e "${RED}错误: 无法更新任务文件${NC}" >&2
        release_lock
        return 1
    fi

    chmod --reference="$JOBS_FILE" "$temp_file"
    mv "$temp_file" "$JOBS_FILE" || {
        rm -f "$temp_file"
        echo -e "${RED}错误: 无法更新任务文件${NC}" >&2
        release_lock
        return 1
    }

    release_lock

    echo -e "${GREEN}✓ 任务重新排序完成${NC}"
    echo -e "   已将第 $n 个等待任务提前到第一位"
    echo ""
    tq_list
}
#}}}

# tq_pause - pause the Nth queued task {{{
tq_pause() {
    local n="$1"

    # Validate the argument
    if [ -z "$n" ]; then
        echo -e "${RED}错误: 请指定任务编号${NC}" >&2
        echo "用法: tq pause <任务编号>" >&2
        return 1
    fi

    # Require a positive integer
    if ! [[ "$n" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}错误: 任务编号必须是数字${NC}" >&2
        return 1
    fi

    if [ "$n" -le 0 ]; then
        echo -e "${RED}错误: 任务编号必须大于0${NC}" >&2
        return 1
    fi

    echo -e "${CYAN}正在暂停第 $n 个等待任务...${NC}"

    if [ ! -f "$JOBS_FILE" ]; then
        echo -e "${YELLOW}任务文件不存在${NC}"
        return 0
    fi

    # Take the queue lock
    if ! acquire_lock "$LOCK_FILE"; then
        return 1
    fi

    # Walk the queue to find the target
    local queue_num=0
    local line_num=0
    while IFS= read -r line || [ -n "$line" ]; do
        ((line_num++))

        # Pause the Nth queued record
        if [[ "$line" == "[ ] "* ]]; then
            ((queue_num++))

            if [ "$queue_num" -eq "$n" ]; then
                sed -Ei "${line_num}s#^\\[ \\]#[?]#" "$JOBS_FILE"
                break
            fi
        fi
    done < "$JOBS_FILE"

    if [ "$n" -gt "$queue_num" ]; then
        echo -e "${RED}错误: 只有 $queue_num 个等待任务，无法暂停第 $n 个${NC}" >&2
        release_lock
        return 1
    fi

    release_lock

    echo -e "${GREEN}✓ 任务暂停完成${NC}"
    echo -e "   已暂停第 $n 个等待任务"
    echo ""
    tq_list
}
#}}}

# tq_pauseall - pause every queued task {{{
tq_pauseall() {
    echo -e "${CYAN}正在暂停未开始的任务...${NC}"

    if [ ! -f "$JOBS_FILE" ]; then
        echo -e "${YELLOW}任务文件不存在${NC}"
        return 0
    fi

    # Take the queue lock
    if ! acquire_lock "$LOCK_FILE"; then
        return 1
    fi

    # Flip every queued prefix to paused
    local unstarted=$(grep -Ec '^\[ \] ' "$JOBS_FILE")
    sed -Ei 's#^\[ \] #[?] #' "$JOBS_FILE"

    release_lock

    echo -e "${GREEN}✓ 暂停完成${NC}"
    echo -e "   已暂停: $unstarted 个未开始任务"
    echo ""
    tq_list
}
#}}}

# tq_resume - resume the Nth paused task {{{
tq_resume() {
    local n="$1"

    # Validate the argument
    if [ -z "$n" ]; then
        echo -e "${RED}错误: 请指定任务编号${NC}" >&2
        echo "用法: tq resume <任务编号>" >&2
        return 1
    fi

    # Require a positive integer
    if ! [[ "$n" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}错误: 任务编号必须是数字${NC}" >&2
        return 1
    fi

    if [ "$n" -le 0 ]; then
        echo -e "${RED}错误: 任务编号必须大于0${NC}" >&2
        return 1
    fi

    echo -e "${CYAN}正在恢复第 $n 个暂停任务...${NC}"

    if [ ! -f "$JOBS_FILE" ]; then
        echo -e "${YELLOW}任务文件不存在${NC}"
        return 0
    fi

    # Take the queue lock
    if ! acquire_lock "$LOCK_FILE"; then
        return 1
    fi

    # Walk the queue to find the target
    local paused_num=0
    local line_num=0
    while IFS= read -r line || [ -n "$line" ]; do
        ((line_num++))

        # Resume the Nth paused record
        if [[ "$line" == "[?] "* ]]; then
            ((paused_num++))

            if [ "$paused_num" -eq "$n" ]; then
                sed -Ei "${line_num}s#^\\[\\?\\]#[ ]#" "$JOBS_FILE"
                break
            fi
        fi
    done < "$JOBS_FILE"

    if [ "$n" -gt "$paused_num" ]; then
        echo -e "${RED}错误: 只有 $paused_num 个暂停任务，无法恢复第 $n 个${NC}" >&2
        release_lock
        return 1
    fi

    release_lock

    echo -e "${GREEN}✓ 任务恢复完成${NC}"
    echo -e "   已恢复第 $n 个暂停任务"
    echo ""
    tq_list
}
#}}}

# tq_resumeall - move every paused task back to the queue {{{
tq_resumeall() {
    echo -e "${CYAN}正在恢复已暂停的任务...${NC}"

    if [ ! -f "$JOBS_FILE" ]; then
        echo -e "${YELLOW}任务文件不存在${NC}"
        return 0
    fi

    # Take the queue lock
    if ! acquire_lock "$LOCK_FILE"; then
        return 1
    fi

    # Flip every paused prefix back to queued
    local paused=$(grep -Ec '^\[\?\] ' "$JOBS_FILE")
    sed -Ei 's#^\[\?\] #[ ] #' "$JOBS_FILE"

    release_lock

    echo -e "${GREEN}✓ 恢复完成${NC}"
    echo -e "   已恢复: $paused 个已暂停任务"
    echo ""
    tq_list
}
#}}}

# tq_clean - delete finished tasks {{{
tq_clean() {
    echo -e "${CYAN}正在清空已结束的任务...${NC}"

    if [ ! -f "$JOBS_FILE" ]; then
        echo -e "${YELLOW}任务文件不存在${NC}"
        return 0
    fi

    # Take the queue lock
    if ! acquire_lock "$LOCK_FILE"; then
        return 1
    fi

    local removed
    removed=$(grep -c '^\[[x!]\] ' "$JOBS_FILE" || true)
    sed -i '/^\[[x!]\] /d' "$JOBS_FILE"

    release_lock

    echo -e "${GREEN}✓ 清空完成${NC}"
    echo -e "   已移除: $removed 个已结束任务"
    echo ""
    tq_list
}
#}}}

# tq_cleanall - delete every task that is not running {{{
tq_cleanall() {
    echo -e "${CYAN}正在清空所有非运行中的任务...${NC}"

    if [ ! -f "$JOBS_FILE" ]; then
        echo -e "${YELLOW}任务文件不存在${NC}"
        return 0
    fi

    if ! acquire_lock "$LOCK_FILE"; then
        return 1
    fi

    local removed
    removed=$(grep -c '^\[[ ?x!]\] ' "$JOBS_FILE" || true)
    sed -i '/^\[[ ?x!]\] /d' "$JOBS_FILE"

    release_lock

    echo -e "${GREEN}✓ 清空完成${NC}"
    echo -e "   已移除: $removed 个非运行中任务"
    echo ""
    tq_list
}
#}}}

# tq_reset - requeue every task that is not running {{{
tq_reset() {
    if [ ! -f "$JOBS_FILE" ]; then
        echo -e "${YELLOW}任务文件不存在或为空${NC}"
        return 0
    fi

    # Take the queue lock
    if ! acquire_lock "$LOCK_FILE"; then
        return 1
    fi

    # Requeue finished and paused records
    local changed=$(grep -Ec '^\[[?x!]\] ' "$JOBS_FILE")
    # Strip timing fields only from finished records; queued commands stay untouched
    sed -Ei 's#^(\[[?x!]\] .*) \[[0-9/]{5} [0-9:]{5}\] \[[0-9hms]*\]( \[[0-9]+:.+\.log\])?$#\1#' "$JOBS_FILE"
    sed -Ei 's#^\[[?x!]\] #[ ] #' "$JOBS_FILE"

    release_lock

    echo -e "${GREEN}✓ 重置完成${NC}"
    echo -e "   已重置: $changed 个非运行中任务"
    echo ""
    tq_list
}
#}}}

# tq_rerun - reset + run {{{
tq_rerun() {
    local tq_dir="$1"
    tq_reset || return 1
    tq_run "$tq_dir"
}
#}}}

# tq_file - print the queue file path {{{
tq_file() {
    echo "$JOBS_FILE"
}
#}}}

# tq_edit - open the queue file in $EDITOR {{{
tq_edit() {
    if [ -z "$EDITOR" ]; then
        echo -e "${RED}错误: 未设置 EDITOR 环境变量${NC}" >&2
        echo "请设置 EDITOR，例如: export EDITOR=vim" >&2
        return 1
    fi

    if [ ! -f "$JOBS_FILE" ]; then
        echo -e "${YELLOW}任务文件不存在，将创建新文件${NC}"
        touch "$JOBS_FILE" || {
            echo -e "${RED}错误: 无法创建任务文件${NC}" >&2
            return 1
        }
    fi

    $EDITOR "$JOBS_FILE"
}
#}}}

# tq_help - print usage {{{
tq_help() {
    echo -e "${CYAN}=== TaskQueue (tq) ===${NC}"
    echo ""
    echo -e "${GREEN}可用命令:${NC}"
    echo "  tq,"
    echo "  tq list        - 显示所有任务状态"
    echo ""
    echo "  tq add <任务>  - 添加任务到队列（将在当前路径下运行）"
    echo "  tq run         - 启动一个新的运行器"
    echo ""
    echo "  tq top <N>     - 将第 N 个等待任务提前到第一位"
    echo "  tq pause <N>   - 暂停第 N 个等待任务"
    echo "  tq pauseall    - 暂停所有未开始的任务"
    echo "  tq resume <N>  - 恢复第 N 个暂停任务"
    echo "  tq resumeall   - 恢复所有已暂停的任务到队列"
    echo "  tq clean       - 清空已结束的任务"
    echo "  tq cleanall    - 清空所有非运行中的任务"
    echo "  tq reset       - 重置所有非运行中的任务到队列"
    echo "  tq rerun       - reset + run"
    echo ""
    echo "  tq file        - 显示队列文件路径"
    echo "  tq edit        - 用编辑器（\$EDITOR）打开任务文件"
    echo "  tq help        - 显示此帮助信息"
    echo ""
    echo "  tql      <子命令>,"
    echo "  tq local <子命令>  - 使用当前目录的队列（./tasks.txt）"
    echo ""
    echo -e "${MAGENTA}配置文件:${NC}"
    echo "  任务文件:    $JOBS_FILE"
    echo "  锁文件:      $LOCK_FILE"
    echo "  运行器脚本:  $RUNNER_SCRIPT"
    echo ""
    echo -e "${BLUE}示例:${NC}"
    echo "  tq add 'find . -name \"*.py\"'"
    echo "  tq run"
}
#}}}

# main - dispatch the subcommand {{{
main() {
    if [ "$1" == "local" ]; then
        shift
        readonly TQ_DIR="$PWD"
    fi
    source "$HOME/opt/taskqueue/common.sh"

    local command="$1"
    case "$command" in
        "list"|"")
            tq_list
            ;;
        "add")
            shift
            tq_add "$@"
            ;;
        "run")
            tq_run "$TQ_DIR"
            ;;
        "top")
            shift
            tq_top "$@"
            ;;
        "pause")
            shift
            tq_pause "$@"
            ;;
        "pauseall")
            tq_pauseall
            ;;
        "resume")
            shift
            tq_resume "$@"
            ;;
        "resumeall")
            tq_resumeall
            ;;
        "clean")
            tq_clean
            ;;
        "cleanall")
            tq_cleanall
            ;;
        "reset")
            tq_reset
            ;;
        "rerun")
            tq_rerun "$TQ_DIR"
            ;;
        "file")
            tq_file
            ;;
        "edit")
            tq_edit
            ;;
        "help")
            tq_help
            ;;
        *)
            echo -e "${RED}未知命令: $command${NC}" >&2
            echo "使用 'tq help' 查看可用命令" >&2
            return 1
            ;;
    esac
}
#}}}

# Run main only when the script is executed, not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
