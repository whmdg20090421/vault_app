# Tasks
- [x] Task 1: 实时加密速度计算
  - [x] SubTask 1.1: 在加密任务管理器或状态模型中增加近5秒的字节数缓存列表。
  - [x] SubTask 1.2: 基于过去5秒的总加密字节数，计算出实时的加密速度，并转换为 KB/s 或 MB/s 的格式字符串。
  - [x] SubTask 1.3: 在加密进度条第2行左侧，在加密进度百分比后面添加括号显示实时速度。
- [x] Task 2: 预计剩余时间计算与 UI 布局优化
  - [x] SubTask 2.1: 缩小进度条第2行右侧当前加密大小的文本的字间距（letterSpacing）。
  - [x] SubTask 2.2: 使用当前的剩余加密字节数除以缓存的实时速度，计算出预计所需的时间（单位为分:秒，如 `02:15`）。
  - [x] SubTask 2.3: 在右侧加密大小后面增加括号显示预计所需时间。
- [x] Task 3: 开发者模式与“关于”页长按功能
  - [x] SubTask 3.1: 在设置页面的“关于” UI 组件上添加长按（LongPress）手势识别器。
  - [x] SubTask 3.2: 设定长按触发条件（例如5秒触发），触发时弹出一个警告对话框，提示“进入开发者模式可能会损坏你的加密文件”。
  - [x] SubTask 3.3: 用户确认后，在全局状态中启用开发者模式（Developer Mode）。
- [x] Task 4: 增加详细 Debug 信息的第3行展示
  - [x] SubTask 4.1: 当处于开发者模式时，在加密进度条下方添加第3行大类展示区。
  - [x] SubTask 4.2: 收集并显示当前使用的加密算法、底层调用情况、底层加密库状态、元数据、线程加密负载等调试信息。
- [x] Task 5: 增加丝滑Q弹的 UI 动画
  - [x] SubTask 5.1: 为进度条、开发者模式面板、弹窗等 UI 元素添加 Spring 物理特性的动画（如 Flutter 的 `Curves.elasticOut` 或相关的弹性动画库）。
  - [x] SubTask 5.2: 确保所有进度条的更新与数值变化有平滑的过渡动画。
- [x] Task 6: 批量检查与代码稳定性测试
  - [x] SubTask 6.1: 检查 `cryptography` 等底层接口调用在多线程或状态更新频繁时的安全性。
  - [x] SubTask 6.2: 确保计算速度或预计时间时不会发生除零错误或内存泄漏。
  - [x] SubTask 6.3: 运行相关集成测试和单元测试，验证应用不会出现崩溃或文件损坏的风险。

# Task Dependencies
- [Task 2] depends on [Task 1]
- [Task 4] depends on [Task 3]
- [Task 6] depends on all other Tasks
