# TaskQueue

极简任务队列管理脚本。

### 恩师

[A Job Queue in 20 Lines of Bash](https://maximerobeyns.com/fragments/job_queue)

TaskQueue 的核心：队列 `tasks.txt` 和 Runner `runner.sh` 均完全采用了 Maxime 的方案和代码实现，轻量、极简且功能完善。TaskQueue 主要的工作是增强对队列和 Runner 的管理。

**建议所有人在使用本工具前都阅读恩师原文。**

恩师其二：DeepSeek (via 腾讯元宝)，95% 的代码都由 DeepSeek 完成。

### `tasks.txt`

记录任务队列及状态的文本文件，有下列几种状态：

- `[ ] <命令>` : 待执行的任务
- `[?] <命令>` : 暂停中的排队任务，接下来不会被执行
- `[-] <命令> [start_date] [R:runner_pid]` : 正在被某个 Runner 执行的任务
- `[x] <命令> [start_date] [elapsed_time]` : 已结束的任务，正常退出
- `[!] <命令> [start_date] [elapsed_time]` : 已结束的任务，异常退出

一般来说不应该手动编辑此文件，请用 `tq add` / `tq run` / `tq clean` 来管理。

### 安装

为了计算任务耗时，系统需安装 `bc` 。

1. `git clone` 或下载本仓库到本地
2. `bash ./install.sh` - 必要文件将会安装到 `$HOME/opt/taskqueue`
3. `echo 'alias tq="bash $HOME/opt/taskqueue/taskqueue.sh"' >> ~/.bashrc`
4. `source ~/.bashrc`
5. `tq help`

### 用法

可用命令:

```
tq, tq list    - 显示所有任务状态
tq add <命令>  - 添加任务到队列（在当前路径下执行）
tq run         - 启动一个新的运行器
tq pause       - 暂停未开始的任务
tq resume      - 恢复已暂停的任务到队列
tq clean       - 清理已完成的任务
tq cleanall    - 清理所有非运行中的任务
tq file        - 输出任务队列文件路径
tq help        - 显示此帮助信息
```

示例：

1. 添加一个测试任务:
   `tq add 'echo "Hello from task queue"'`

2. 启动运行器:
   `tq run`

3. 查看任务状态:
   `tq`

### 小贴士

你可以多次调用 `tq run` 来增加并行度！
