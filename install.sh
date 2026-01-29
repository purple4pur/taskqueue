#!/usr/bin/env bash

# ============================================
# TaskQueue 任务队列系统 - 安装和配置脚本
# ============================================

set -e  # 遇到错误立即退出

echo "开始安装 TaskQueue 任务队列系统..."
echo ""

# 基础目录
BASE_DIR="$HOME/opt/taskqueue"
SCRIPTS=("taskqueue.sh" "runner.sh" "common.sh")

# 创建必要的目录
echo "创建目录结构..."
mkdir -p "$BASE_DIR"

# 检查脚本是否存在
for script in "${SCRIPTS[@]}"; do
    if [ ! -f "$script" ]; then
        echo "错误: 找不到脚本 $script"
        echo "请确保所有脚本在同一目录下"
        exit 1
    fi
done

# 复制脚本到目标目录
echo "复制脚本到 $BASE_DIR..."
cp taskqueue.sh "$BASE_DIR/"
cp runner.sh "$BASE_DIR/"
cp common.sh "$BASE_DIR/"

# 设置执行权限
echo "设置执行权限..."
chmod +x "$BASE_DIR/taskqueue.sh"
chmod +x "$BASE_DIR/runner.sh"
chmod +x "$BASE_DIR/common.sh"

# 创建任务文件（如果不存在）
TASKS_FILE="$BASE_DIR/tasks.txt"
if [ ! -f "$TASKS_FILE" ]; then
    echo "创建任务文件: $TASKS_FILE"
    touch "$TASKS_FILE"
    chmod 0600 "$TASKS_FILE"
else
    echo "任务文件已存在: $TASKS_FILE"
fi

# 安装完成信息
echo ""
echo "==========================================="
echo "TaskQueue 安装完成！"
echo "==========================================="
echo ""
echo "安装目录: $BASE_DIR"
echo ""
echo "可用文件:"
echo "  taskqueue.sh  - 主功能"
echo "  runner.sh     - 任务运行器"
echo "  tasks.txt     - 任务队列文件"
echo "  common.sh     - 公共配置及功能"
echo ""
echo "快速开始:"
echo "1. 添加别名到您的 shell 配置:"
echo "   echo 'alias tq=\"bash \$HOME/opt/taskqueue/taskqueue.sh\"' >> ~/.bashrc"
echo "   source ~/.bashrc"
echo ""
echo "2. 添加一个测试任务:"
echo "   tq add 'echo \"Hello from task queue\"'"
echo ""
echo "3. 启动运行器:"
echo "   tq run"
echo ""
echo "4. 查看任务状态:"
echo "   tq"
echo ""
echo "==========================================="
