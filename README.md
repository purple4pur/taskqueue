# TaskQueue

极简任务队列管理脚本。

### 恩师

[A Job Queue in 20 Lines of Bash](https://maximerobeyns.com/fragments/job_queue)

TaskQueue 的核心：队列 `tasks.txt` 和 Runner `runner.sh` 均完全采用了 Maxime 的方案和代码实现，轻量、极简且功能完善。TaskQueue 主要的工作是增强对于队列和 Runner 的管理。

恩师其二：DeepSeek (via 腾讯元宝)，95% 的代码都由 DeepSeek 完成。

### 安装

1. `git clone` 或下载本仓库到本地
2. `chmod +x install.sh`
3. `./install.sh` - 必要文件将会安装到 `$HOME/opt/taskqueue`
4. `echo 'alias tq="bash $HOME/opt/taskqueue/taskqueue.sh"' >> ~/.bashrc`
5. `source ~/.bashrc`
6. `tq help`

### 用法

可用命令:

```
tq list        - 显示所有任务状态
tq add <命令>  - 添加任务到队列（在当前路径下执行）
tq run         - 启动一个新的 Runner
tq clean       - 清理已完成的任务
tq help        - 显示此帮助信息
```

例子：

TODO
