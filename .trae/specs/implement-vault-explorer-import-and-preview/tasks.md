# Tasks

- [x] Task 1: 盘点与定义“待开发”功能清单
  - [x] SubTask 1.1: 在代码中定位所有“开发中/待开发”提示的入口与调用链
  - [x] SubTask 1.2: 明确每个入口的最小可用行为（导入文件、导入文件夹、文件预览/导出）

- [x] Task 2: 实现导入明文文件（多选）
  - [x] SubTask 2.1: 在 `VaultExplorerPage` 中实现将选中文件导入 `_currentPath`（调用 VFS upload）
  - [x] SubTask 2.2: 增加导入进度 UI 与取消能力（最小实现）
  - [x] SubTask 2.3: 导入完成后刷新列表并处理错误提示

- [x] Task 3: 实现导入明文文件夹（递归）
  - [x] SubTask 3.1: 递归扫描本地目录并在目标路径创建对应目录结构（调用 VFS mkdir/upload）
  - [x] SubTask 3.2: 增加导入进度 UI 与取消能力（复用 Task 2 的方案）
  - [x] SubTask 3.3: 导入完成后刷新列表并处理错误提示

- [x] Task 4: 实现文件读取（预览/导出）
  - [x] SubTask 4.1: 点击文件时弹出操作面板（预览文本/导出临时目录）
  - [x] SubTask 4.2: 实现文本预览（读取前 N 字节并 UTF-8 解码；失败则提示）
  - [x] SubTask 4.3: 实现导出到临时目录（写入临时文件并提示保存结果）

- [ ] Task 5: 验证与回归
  - [ ] SubTask 5.1: 验证在启用/不启用文件名加密时导入路径与文件名符合预期
  - [ ] SubTask 5.2: 验证导入大文件/多文件时 UI 不长时间无响应（至少有加载提示）
  - [ ] SubTask 5.3: 验证预览/导出对常见文本文件可用，对二进制文件给出合理提示

# Task Dependencies
- [Task 2] depends on [Task 1]
- [Task 3] depends on [Task 2]
- [Task 4] depends on [Task 1]
- [Task 5] depends on [Task 2], [Task 3], [Task 4]
