# Tasks
- [x] Task 1: 优化加密速度与剩余时间计算逻辑
  - [x] SubTask 1.1: 在 `EncryptionTaskManager` 中引入 10 秒的滑动窗口数据结构（记录时间戳与对应处理的字节增量）。
  - [x] SubTask 1.2: 根据窗口内的数据计算实时加密速度（如果总时间小于 10 秒，则使用全局平均速度）。
  - [x] SubTask 1.3: 更新 ETA（剩余时间）的计算逻辑，使用新的实时速度进行预估。
- [x] Task 2: 增加加密分配策略设置
  - [x] SubTask 2.1: 在 `performance_settings_page.dart` 中增加三个单选选项（仅硬件、仅软件、智能分配）。
  - [x] SubTask 2.2: 将用户的选择持久化保存至 `SharedPreferences`。
  - [x] SubTask 2.3: 在任务分配逻辑中读取该配置，并严格按照该配置调度分配硬件或软件 Worker。
- [x] Task 3: 优化加密进度条 UI 与动画更新
  - [x] SubTask 3.1: 修复 `encryption_progress_panel.dart` 中的 CustomPainter，在 `completedSize` 和 `encryptingCompletedSize` 之间绘制一条极细的白色竖线。
  - [x] SubTask 3.2: 为正在加密的部分（`encryptingCompletedSize`）使用渐变色绘制（如亮绿色至黄绿色的过渡），而完全加密部分保持纯绿色。
  - [x] SubTask 3.3: 确保底层在处理加密块（chunk）完成时及时触发 UI 刷新（例如在加密循环中定期调用 notifyListeners()），使得进度条平滑移动。

# Task Dependencies
- Task 1, Task 2, Task 3 可相对独立并行开发。
