# Tasks
- [x] Task 1: 修复长按“关于”键进入开发者模式的逻辑
  - [x] SubTask 1.1: 检查 `vault_config_page.dart` (或相关设置页面) 中关于“关于”选项的长按手势识别（GestureDetector 的 onLongPress）
  - [x] SubTask 1.2: 确保长按 5 秒的时间阈值逻辑正确触发开发者模式警告弹窗。
- [x] Task 2: 优化文件夹的加密模式标签展示
  - [x] SubTask 2.1: 在 `encryption_progress_panel.dart` 中，当节点为文件夹时，遍历其子任务的状态，汇总其加密模式（硬件/普通）。
  - [x] SubTask 2.2: 在文件夹的进度条 UI 上方正确渲染这些加密模式标签。
- [x] Task 3: 修改加密界面加号按钮的交互逻辑
  - [x] SubTask 3.1: 在加密主界面中找到 FloatingActionButton 的 onPressed 事件。
  - [x] SubTask 3.2: 移除直接调用系统文件选择器的代码，改为弹出一个 ModalBottomSheet 或 PopupMenu。
  - [x] SubTask 3.3: 菜单的第一项设置为“创建加密文件夹”，其他选项保留原有的文件导入功能。
- [x] Task 4: 在性能设置中增加“兼容性测试”
  - [x] SubTask 4.1: 在设置页面的性能设置部分增加一个“兼容性测试”列表项。
  - [x] SubTask 4.2: 实现测试逻辑：分别生成随机数据，使用 FlutterCryptography (硬件) 和纯 Dart (软件) 进行加密测速。
  - [x] SubTask 4.3: 将测试结果（可用性、MB/s）以弹窗或新页面的形式展示给用户。

# Task Dependencies
- Task 1, Task 2, Task 3, Task 4 是独立的，可并行开发。
