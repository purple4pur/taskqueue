#!/usr/bin/env bash

source $HOME/opt/taskqueue/common.sh

# 显示所有任务状态
tq_list() {
    echo -e "${CYAN}=== 任务队列状态 ($(date '+%Y-%m-%d %H:%M:%S')) ===${NC}"
    echo -e "${GREEN}文件: $JOBS_FILE${NC}"
    echo ""

    if [ ! -f "$JOBS_FILE" ]; then
        echo -e "${YELLOW}任务文件不存在或为空${NC}"
        return 0
    fi

    # 读取并显示所有任务
    local queue_order=1
    while IFS= read -r line || [ -n "$line" ]; do
        local status="未知"
        local task_info=""

        # 解析任务状态
        if [[ "$line" =~ ^\[[[:space:]]\] ]]; then
            status=$(printf "${CYAN}%3s${NC}" "Q$queue_order")
            ((queue_order++))
        elif [[ "$line" =~ ^\[\?\] ]]; then
            status="${MAGENTA}PAU${NC}"
        elif [[ "$line" =~ ^\[-\] ]]; then
            status="${YELLOW}RUN${NC}"
        elif [[ "$line" =~ ^\[x\] ]]; then
            status="${GREEN}SUC${NC}"
        elif [[ "$line" =~ ^\[\!\] ]]; then
            status="${RED}FAI${NC}"
        else
            status="${GRAY}UNK${NC}"
        fi

        # 彩色输出开始时间、运行器ID、消耗时间
        line=$(echo "$line" | sed -E "s#(\\[[0-9/]{5} [0-9:]{5}\\])#\\${MAGENTA}\\1\\${NC}#")
        line=$(echo "$line" | sed -E "s#(\\[R:[0-9]+\\])#\\${YELLOW}\\1\\${NC}#")
        line=$(echo "$line" | sed -E "s#(\\[[0-9hm]+s\\])#\\${CYAN}\\1\\${NC}#")

        # 显示任务信息
        echo -e "$status $line"
    done < "$JOBS_FILE"
}

# 添加任务到队列
tq_add() {
    if [ $# -eq 0 ]; then
        echo -e "${RED}错误: 请提供要执行的命令${NC}" >&2
        echo "用法: tq add <命令>" >&2
        return 1
    fi

    # 获取当前工作目录
    local current_dir
    current_dir=$(pwd) || {
        echo -e "${RED}错误: 无法获取当前目录${NC}" >&2
        return 1
    }

    # 验证当前目录安全
    if [[ "$current_dir" =~ \.\. ]]; then
        echo -e "${RED}错误: 当前目录路径包含非法字符${NC}" >&2
        return 1
    fi

    local command="$*"

    # 安全构建任务命令
    local safe_dir
    safe_dir=$(safe_quote "$current_dir")

    local full_command="cd $safe_dir && $command"

    # 获取文件锁以避免并发写入问题
    if ! acquire_lock "$LOCK_FILE"; then
        return 1
    fi

    # 安全写入任务文件
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

# 启动新的运行器
tq_run() {
    bash "$RUNNER_SCRIPT"
}

# 暂停未开始的任务
tq_pause() {
    echo -e "${CYAN}正在暂停未开始的任务...${NC}"

    if [ ! -f "$JOBS_FILE" ]; then
        echo -e "${YELLOW}任务文件不存在${NC}"
        return 0
    fi

    # 获取文件锁
    if ! acquire_lock "$LOCK_FILE"; then
        return 1
    fi

    # 更改未开始任务状态
    local unstarted=$(grep -Ec '^\[ \] ' "$JOBS_FILE")
    sed -Ei 's#^\[ \] #[?] #' "$JOBS_FILE"

    release_lock

    echo -e "${GREEN}✓ 暂停完成${NC}"
    echo -e "   已暂停: $unstarted 个未开始任务"
}

# 恢复已暂停的任务到队列
tq_resume() {
    echo -e "${CYAN}正在恢复已暂停的任务...${NC}"

    if [ ! -f "$JOBS_FILE" ]; then
        echo -e "${YELLOW}任务文件不存在${NC}"
        return 0
    fi

    # 获取文件锁
    if ! acquire_lock "$LOCK_FILE"; then
        return 1
    fi

    # 更改已暂停任务状态
    local paused=$(grep -Ec '^\[\?\] ' "$JOBS_FILE")
    sed -Ei 's#^\[\?\] #[ ] #' "$JOBS_FILE"

    release_lock

    echo -e "${GREEN}✓ 恢复完成${NC}"
    echo -e "   已恢复: $paused 个已暂停任务"
}

# 清理已完成的任务
tq_clean() {
    echo -e "${CYAN}正在清理已完成的任务...${NC}"

    if [ ! -f "$JOBS_FILE" ]; then
        echo -e "${YELLOW}任务文件不存在${NC}"
        return 0
    fi

    # 获取文件锁
    if ! acquire_lock "$LOCK_FILE"; then
        return 1
    fi

    # 安全过滤任务
    local temp_file
    temp_file=$(mktemp) || {
        echo -e "${RED}错误: 无法创建临时文件${NC}" >&2
        release_lock
        return 1
    }

    # 只保留非完成状态的任务
    grep -v "^\[[x!]\] " "$JOBS_FILE" > "$temp_file"

    local original_count
    original_count=$(wc -l < "$JOBS_FILE" 2>/dev/null || echo "0")
    local new_count
    new_count=$(wc -l < "$temp_file" 2>/dev/null || echo "0")
    local removed=$((original_count - new_count))

    # 安全替换原文件
    mv "$temp_file" "$JOBS_FILE" || {
        echo -e "${RED}错误: 无法更新任务文件${NC}" >&2
        release_lock
        return 1
    }

    release_lock

    echo -e "${GREEN}✓ 清理完成${NC}"
    echo -e "   已移除: $removed 个已结束任务"
}

# 清理所有非运行中的任务
tq_cleanall() {
    echo -e "${CYAN}正在清理所有非运行中的任务...${NC}"

    if [ ! -f "$JOBS_FILE" ]; then
        echo -e "${YELLOW}任务文件不存在${NC}"
        return 0
    fi

    # 获取文件锁
    if ! acquire_lock "$LOCK_FILE"; then
        return 1
    fi

    # 安全过滤任务
    local temp_file
    temp_file=$(mktemp) || {
        echo -e "${RED}错误: 无法创建临时文件${NC}" >&2
        release_lock
        return 1
    }

    # 只保留运行中的任务
    grep -v "^\[[ ?x!]\] " "$JOBS_FILE" > "$temp_file"

    local original_count
    original_count=$(wc -l < "$JOBS_FILE" 2>/dev/null || echo "0")
    local new_count
    new_count=$(wc -l < "$temp_file" 2>/dev/null || echo "0")
    local removed=$((original_count - new_count))

    # 安全替换原文件
    mv "$temp_file" "$JOBS_FILE" || {
        echo -e "${RED}错误: 无法更新任务文件${NC}" >&2
        release_lock
        return 1
    }

    release_lock

    echo -e "${GREEN}✓ 清理完成${NC}"
    echo -e "   已移除: $removed 个非运行中任务"
}

# 将第N个等待任务提前到第一位
tq_top() {
    local n="$1"

    # 检查参数
    if [ -z "$n" ]; then
        echo -e "${RED}错误: 请指定任务编号${NC}" >&2
        echo "用法: tq top <任务编号>" >&2
        return 1
    fi

    # 验证参数是否为数字
    if ! [[ "$n" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}错误: 任务编号必须是数字${NC}" >&2
        return 1
    fi

    if [ "$n" -le 0 ]; then
        echo -e "${RED}错误: 任务编号必须大于0${NC}" >&2
        return 1
    fi

    echo -e "${CYAN}正在将第 $n 个等待任务提前到第一位...${NC}"

    if [ ! -f "$JOBS_FILE" ]; then
        echo -e "${YELLOW}任务文件不存在${NC}"
        return 0
    fi

    # 获取文件锁
    if ! acquire_lock "$LOCK_FILE"; then
        return 1
    fi

    # 创建临时文件
    local temp_file
    temp_file=$(mktemp) || {
        echo -e "${RED}错误: 无法创建临时文件${NC}" >&2
        release_lock
        return 1
    }

    # 分离等待任务、已暂停任务、未知状态任务和其他状态任务
    local other_tasks=()
    local waiting_tasks=()
    local paused_tasks=()
    local unknown_tasks=()
    local waiting_count=0

    # 读取所有任务
    while IFS= read -r line || [ -n "$line" ]; do
        if [[ "$line" =~ ^\[[[:space:]]\] ]]; then
            # 等待任务
            waiting_tasks+=("$line")
            ((waiting_count++))
        elif [[ "$line" =~ ^\[\?\] ]]; then
            # 已暂停任务
            paused_tasks+=("$line")
        elif [[ "$line" =~ ^\[-\] ]] || [[ "$line" =~ ^\[x\] ]] || [[ "$line" =~ ^\[\!\] ]]; then
            # 其他已知状态任务（运行中、成功、失败）
            other_tasks+=("$line")
        else
            # 未知状态任务
            unknown_tasks+=("$line")
        fi
    done < "$JOBS_FILE"

    # 检查n是否有效
    if [ "$n" -gt "$waiting_count" ]; then
        echo -e "${RED}错误: 只有 $waiting_count 个等待任务，无法移动第 $n 个${NC}" >&2
        rm -f "$temp_file"
        release_lock
        return 1
    fi

    # 重新排序等待任务
    if [ "$waiting_count" -gt 0 ] && [ "$n" -le "$waiting_count" ]; then
        # 找到要提前的任务
        local target_task="${waiting_tasks[$((n-1))]}"

        # 从数组中移除该任务
        unset "waiting_tasks[$((n-1))]"

        # 重新构建数组（移除空元素）
        local new_waiting_tasks=()
        for task in "${waiting_tasks[@]}"; do
            if [ -n "$task" ]; then
                new_waiting_tasks+=("$task")
            fi
        done
        waiting_tasks=("${new_waiting_tasks[@]}")

        # 将目标任务放到等待任务列表的最前面
        waiting_tasks=("$target_task" "${waiting_tasks[@]}")
    fi

    # 写入临时文件：先写其他状态任务，再写等待任务，再写已暂停任务，最后写未知状态任务
    for task in "${other_tasks[@]}"; do
        echo "$task" >> "$temp_file"
    done

    for task in "${waiting_tasks[@]}"; do
        echo "$task" >> "$temp_file"
    done

    for task in "${paused_tasks[@]}"; do
        echo "$task" >> "$temp_file"
    done

    for task in "${unknown_tasks[@]}"; do
        echo "$task" >> "$temp_file"
    done

    # 统计移动情况
    local original_waiting_count="$waiting_count"
    local new_waiting_count="${#waiting_tasks[@]}"

    if [ "$original_waiting_count" -ne "$new_waiting_count" ]; then
        echo -e "${YELLOW}警告: 等待任务数量发生变化 ($original_waiting_count -> $new_waiting_count)${NC}" >&2
    fi

    # 安全替换原文件
    mv "$temp_file" "$JOBS_FILE" || {
        echo -e "${RED}错误: 无法更新任务文件${NC}" >&2
        release_lock
        return 1
    }

    release_lock

    echo -e "${GREEN}✓ 任务重新排序完成${NC}"
    echo -e "   已将第 $n 个等待任务提前到第一位"
}

# 输出任务队列文件路径
tq_file() {
    echo "$JOBS_FILE"
}

# 显示帮助信息
tq_help() {
    echo -e "${CYAN}=== TaskQueue (tq) ===${NC}"
    echo ""
    echo -e "${GREEN}可用命令:${NC}"
    echo "  tq, tq list    - 显示所有任务状态"
    echo "  tq add <命令>  - 添加任务到队列（将在当前路径下执行）"
    echo "  tq run         - 启动一个新的运行器"
    echo "  tq top <N>     - 将第 N 个等待任务提前到第一位"
    echo "  tq pause       - 暂停未开始的任务"
    echo "  tq resume      - 恢复已暂停的任务到队列"
    echo "  tq clean       - 清理已完成的任务"
    echo "  tq cleanall    - 清理所有非运行中的任务"
    echo "  tq file        - 输出任务队列文件路径"
    echo "  tq help        - 显示此帮助信息"
    echo ""
    echo -e "${MAGENTA}配置文件:${NC}"
    echo "  任务文件:    $JOBS_FILE"
    echo "  运行器脚本:  $RUNNER_SCRIPT"
    echo ""
    echo -e "${BLUE}示例:${NC}"
    echo "  tq add 'find . -name \"*.py\"'"
    echo "  tq run"
}

# 主函数
main() {
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
            shift
            tq_run "${1:-1}"
            ;;
        "top")
            shift
            tq_top "$@"
            ;;
        "pause")
            tq_pause
            ;;
        "resume")
            tq_resume
            ;;
        "clean")
            tq_clean
            ;;
        "cleanall")
            tq_cleanall
            ;;
        "file")
            tq_file
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

# 如果直接运行脚本，执行主函数
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
