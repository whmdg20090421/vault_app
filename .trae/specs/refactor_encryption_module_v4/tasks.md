# Tasks
- [ ] Task 1: 定义核心加密数据模型。
  - [ ] SubTask 1.1: 创建 `lib/encryption/models/encryption_node.dart`，包含基于 `folder`/`file` 类型的 JSON 序列化、字段（如 `taskId`, `isPaused`, `rawSize`, `size`, `status` 枚举）。
- [ ] Task 2: 实现全局任务队列持久化与动态状态机管理。
  - [ ] SubTask 2.1: 在 `EncryptionTaskManager` 中实现对活跃任务列表的增删改查、层级展开生成逻辑，并确保断点重启时能重置 `encrypting` 到 `pending_waiting` 或扫描错误文件。
- [ ] Task 3: 重构多线程加密执行器。
  - [ ] SubTask 3.1: 基于用户设置的线程数，实现并行调度池。读取 `status=pending_waiting` 且 `isPaused=false` 的节点进行处理。
  - [ ] SubTask 3.2: 完善加密流程中的文件异常捕获，发生缺失或损坏时将对应节点置为 `error` 而不阻塞其他文件。
- [ ] Task 4: 实现动态进度刷新机制（核心优化）。
  - [ ] SubTask 4.1: 实现独立的后台监听线程。在前台显示时切换为 0.5~1 秒的高频全量刷新；后台静默时切换为 5~10 秒的低频刷新。
  - [ ] SubTask 4.2: 实现任务全完成后的终态缓存与监听线程停止机制。
- [ ] Task 5: 构建主页导航栏加密信息总览 UI。
  - [ ] SubTask 5.1: 实现四色小型进度条图标（计算 `rawSize` 占比，实现小于 1% 强制 1 像素显示的逻辑），并加入提示数值逻辑。
- [ ] Task 6: 构建层级化加密进度详情模态框。
  - [ ] SubTask 6.1: 创建从下往上滑入的半屏模态框，基于结构树支持无限级嵌套展开折叠。
  - [ ] SubTask 6.2: 实现每个条目的三行紧凑布局：名称（含异常图标）+ 操作按钮、极细四色进度条、百分比与数量统计行。
  - [ ] SubTask 6.3: 实现条目级暂停/继续的级联控制功能，以及长按弹出的「移除加密」/「标记为已修复」二次确认菜单功能。
- [ ] Task 7: 实现任务完成归档与哈希入库后处理。
  - [ ] SubTask 7.1: 根节点全完成时触发目录存在性检查，缺失则标记 `error`，存在则移入历史记录。
  - [ ] SubTask 7.2: 在单个文件完成（或任务归档）后，计算密文哈希并结合 `taskId` 与相对路径写入本地哈希索引库。

# Task Dependencies
- [Task 1] 必须首先完成。
- [Task 2] 和 [Task 3] depends on [Task 1].
- [Task 4] depends on [Task 2].
- [Task 5] 和 [Task 6] depends on [Task 4].
- [Task 7] depends on [Task 3].
