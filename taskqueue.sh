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

    cat $JOBS_FILE
    return 0
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
    grep -v "^\[[x!]\]" "$JOBS_FILE" > "$temp_file"

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

# 显示帮助信息
tq_help() {
    echo -e "${CYAN}=== TaskQueue (tq) ===${NC}"
    echo ""
    echo -e "${GREEN}可用命令:${NC}"
    echo "  tq, tq list    - 显示所有任务状态"
    echo "  tq add <命令>  - 添加任务到队列（在当前路径下执行）"
    echo "  tq run         - 启动一个新的运行器"
    echo "  tq clean       - 清理已完成的任务"
    echo "  tq help        - 显示此帮助信息"
    echo ""
    echo -e "${MAGENTA}配置文件:${NC}"
    echo "  任务文件:    $JOBS_FILE"
    echo "  运行器脚本:  $RUNNER_SCRIPT"
    echo ""
    echo -e "${BLUE}示例:${NC}"
    echo "  tq add 'find . -name \"*.py\"'"
    echo "  tq run"
    echo "  tq list"
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
        "clean")
            tq_clean
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
