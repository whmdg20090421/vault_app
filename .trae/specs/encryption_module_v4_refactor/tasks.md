# Tasks
- [ ] Task 1: 建立文件树模型与持久化基础
  - [ ] SubTask 1.1: 新增 `lib/encryption/models/encryption_node.dart`，定义 `EncryptionNode` (基类), `FolderNode`, `FileNode` 及 `EncryptionStatus` 枚举。
  - [ ] SubTask 1.2: 实现节点的 JSON 序列化与反序列化，并包含 `size`, `rawSize`, `isPaused` 等字段。
  - [ ] SubTask 1.3: 实现递归解析本地导入路径，生成包含唯一 `taskId` 的根节点及子树，并存入内部私有目录的任务列表文件中。
- [ ] Task 2: 实现多线程加密调度核心 (`EncryptionTaskManager`)
  - [ ] SubTask 2.1: 初始化线程池，读取用户配置并发数，循环扫描全局树状列表中 `status=pending_waiting` 且 `isPaused=false` 的节点。
  - [ ] SubTask 2.2: 接入 `ChunkCrypto` 进行实际加密，更新文件节点状态 (`encrypting`, `completed`, `error`) 并将最终哈希和结构记录至 `local_index.json`。
  - [ ] SubTask 2.3: 实现加密中断的错误捕获与重启后恢复逻辑（清除非完成状态，重新入列），以及检测缺失文件的自动 `error` 标记。
- [ ] Task 3: 构建全局状态动态刷新机制
  - [ ] SubTask 3.1: 实现后台静默刷新（5~10秒）与前台高频刷新（0.5~1秒）的全局定时器控制。
  - [ ] SubTask 3.2: 根据根节点及子树计算四色（绿、黄、红、灰）的字节总大小及百分比，实现最小 1% 显示逻辑，并缓存最终结果以停止无效刷新。
- [ ] Task 4: 开发主页导航栏加密进度总览 UI
  - [ ] SubTask 4.1: 在主页导航栏添加四色进度条图标，展示基于 3.2 计算的总大小百分比，点击显示数值详情（如：1.5GB/2.0GB）。
- [ ] Task 5: 开发层级化加密进度详情模态框 UI
  - [ ] SubTask 5.1: 编写底部滑出的半屏模态框 `EncryptionProgressModal`，展示所有根节点的树状层级。
  - [ ] SubTask 5.2: 实现条目的三行紧凑布局（包含操作按钮、四色进度条、百分比及 1/1 或 N/M 数量统计）。
  - [ ] SubTask 5.3: 实现节点级的暂停/继续功能（更新本节点及子节点 `isPaused` 并终止运行线程）。
  - [ ] SubTask 5.4: 实现长按操作菜单（移除加密/标记为已修复），并在任务 100% 验证完成后自动归档至历史记录。

# Task Dependencies
- [Task 1] 是所有后续任务的基础。
- [Task 2] depends on [Task 1]。
- [Task 3] depends on [Task 1] 和 [Task 2]。
- [Task 4] depends on [Task 3]。
- [Task 5] depends on [Task 3] 和 [Task 2]。
