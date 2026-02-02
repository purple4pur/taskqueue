# TaskQueue

极简任务队列管理脚本。

### 恩师

[A Job Queue in 20 Lines of Bash](https://maximerobeyns.com/fragments/job_queue)

TaskQueue 的核心：队列 `tasks.txt` 和 Runner `runner.sh` 均完全采用了 Maxime 的方案和代码实现，轻量、极简且功能完善。TaskQueue 主要的工作是增强对队列和 Runner 的管理。

**建议所有人在使用本工具前都阅读恩师原文。**

恩师其二：DeepSeek (via 腾讯元宝)，95% 的代码都由 DeepSeek 完成。

### 队列文件 `tasks.txt`

记录任务队列及当前状态的文本文件，有以下几种表示：

- `[ ] <命令>` - 正在排队等待运行的任务
- `[?] <命令>` - 暂停中的任务，还没开始，但不参与排队
- `[-] <命令> [start_date] [R:runner_pid]` - 正在被某个 Runner 运行的任务
- `[x] <命令> [start_date] [elapsed_time]` - 已结束的任务，正常退出
- `[!] <命令> [start_date] [elapsed_time]` - 已结束的任务，异常退出

一般来说不应该手动编辑此文件，请用 `tq add` / `tq run` 等命令来管理。

### 安装 / 升级

为了计算任务耗时，系统需安装 `bc` 。

1. `git clone` 或下载本仓库到本地
2. `bash ./install.sh` - 必要文件将会复制到 `$HOME/opt/taskqueue`
3. `echo 'alias tq="bash $HOME/opt/taskqueue/taskqueue.sh"' >> ~/.bashrc`
4. `source ~/.bashrc`
5. `tq help`

### 用法

```
  tq, tq list    - 显示所有任务状态
  tq add <命令>  - 添加任务到队列（将在当前路径下运行）
  tq run         - 启动一个新的运行器
  tq top <N>     - 将第 N 个等待任务提前到第一位
  tq pauseall    - 暂停所有未开始的任务
  tq resumeall   - 恢复所有已暂停的任务到队列
  tq clean       - 清空已结束的任务
  tq cleanall    - 清空所有非运行中的任务
  tq file        - 显示队列文件路径
  tq help        - 显示此帮助信息
```

每当启动一个新的运行器，运行器将会找到队列中第一个正在排队的任务并启动运行。当前任务结束后将再次寻找，直到队列中不再有排队任务，然后自动退出。

示例：

1. 添加一个测试任务：
   `tq add 'echo "Hello from task queue"'`

2. 启动运行器：
   `tq run`

3. 查看任务状态：
   `tq`

### 小贴士

你可以多次调用 `tq run` 来增加并行度！
