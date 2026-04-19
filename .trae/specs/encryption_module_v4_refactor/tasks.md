# Tasks

- [ ] Task 1: 建立文件树模型与持久化基础 (对应需求一、二)
  - [ ] SubTask 1.1: 创建 `EncryptionNode` 及其子类 `FolderNode`, `FileNode`。包含字段：`taskId` (仅根), `name`, `type`, `isPaused` (布尔), `children` (仅 folder), `size` (自动换算1~1000的B~TB), `rawSize`, `status` (pending_waiting, pending_paused, encrypting, completed, error)。
  - [ ] SubTask 1.2: 编写基于用户选择的绝对路径递归遍历构建树的逻辑，生成唯一 `taskId`，同步读取文件大小并自动换算 `size`，初始化状态 (`isPaused=false`, `status=pending_waiting`)。
  - [ ] SubTask 1.3: 实现全局任务列表的 JSON 序列化与持久化（保存至应用内部私有数据目录），在新建任务后触发写入并启动动态刷新机制。

- [ ] Task 2: 实现多线程加密执行与状态更新核心 (对应需求三、四、九)
  - [ ] SubTask 2.1: 读取预设加密线程数，实现线程池并行处理所有任务中 `status=pending_waiting` 且 `isPaused=false` 的文件节点，开始时将状态置为 `encrypting`。
  - [ ] SubTask 2.2: 接入加密逻辑，处理完成后将状态置为 `completed`，计算哈希值，并将哈希值与文件唯一标识 (`taskId + 相对路径`) 关联写入本地哈希索引库。
  - [ ] SubTask 2.3: 实现异常与中断处理：文件缺失/损坏/无法读取时立即终止该文件进程、标为 `error` 并在 UI 抛出异常；系统异常中断重启后，将中断文件重置为 `pending_waiting` 并支持自动读取重新完整加密，对原文件系统中不存在的文件标记为 `error`。

- [ ] Task 3: 构建动态进度刷新机制 (对应需求七)
  - [ ] SubTask 3.1: 编写独立监听线程进行全局进度计算与更新（不直接操作UI），将进度状态持久化。
  - [ ] SubTask 3.2: 实现前台高频刷新（有进度UI打开时，全量刷新后每0.5~1秒随机刷新一次更新UI与内存）。
  - [ ] SubTask 3.3: 实现后台静默刷新（无进度UI打开时，每5~10秒随机刷新一次，仅更新内存与持久化不重绘UI）。
  - [ ] SubTask 3.4: 无活跃任务时触发最终全量刷新并永久缓存，停止所有定时刷新任务。

- [ ] Task 4: 开发主页导航栏加密信息总览 UI (对应需求五)
  - [ ] SubTask 4.1: 在主页导航栏放置小型四色进度条图标，根据 `completed`(绿)、`encrypting`(黄)、`pending_waiting`(红)、`pending_paused`+`error`(灰) 的 `rawSize` 之和计算占比。
  - [ ] SubTask 4.2: 实现进度条强制可视化规则（任一颜色占比<1%但存在数据时强制显示至少1像素长度），点击时显示数值提示（如 已加密大小/总大小）。

- [ ] Task 5: 开发层级化加密进度详情模态框 UI (对应需求六)
  - [ ] SubTask 5.1: 实现由主界面「查看同步进度」按钮触发的下往上滑出半屏模态框，展示所有同级关系的任务根节点及多级嵌套折叠结构。
  - [ ] SubTask 5.2: 实现三行紧凑条目布局：左侧暂停/继续按钮+名称(异常红感叹号)、极细四色进度条(遵循1%最小宽度规则)、左侧整体加密百分比+右侧数量统计(文件固定1/1，文件夹统计文件数不含自身)。
  - [ ] SubTask 5.3: 实现节点级的暂停/继续逻辑：暂停时中止自身及子节点正在运行线程、置 `isPaused=true` 及状态转为 `pending_paused`；继续时恢复 `pending_waiting` 并入列。父节点操作覆盖子节点。
  - [ ] SubTask 5.4: 实现长按操作菜单：支持「移除加密」及「标记为已修复」。移除时终止线程、从列表永久移除该节点及子节点并更新进度（需二次确认）。

- [ ] Task 6: 任务完成与自动归档 (对应需求八)
  - [ ] SubTask 6.1: 监控任务根节点状态，当所有文件节点为 `completed` 时，执行原文件系统目录存在性检查。
  - [ ] SubTask 6.2: 若所有文件/文件夹存在，将任务移至加密历史记录永久保存；若存在缺失，保留在活跃列表并将缺失文件标 `error`。
  - [ ] SubTask 6.3: 实现加密历史记录列表 UI 及长按「删除历史」功能（二次确认，仅清数据不删文件和索引）。

# Task Dependencies
- [Task 1] 是所有后续任务的数据结构基础。
- [Task 2] depends on [Task 1]。
- [Task 3] depends on [Task 1] 和 [Task 2]。
- [Task 4] depends on [Task 3]。
- [Task 5] depends on [Task 3] 和 [Task 2]。
- [Task 6] depends on [Task 2] 和 [Task 5]。
