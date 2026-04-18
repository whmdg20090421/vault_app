# 修复多线程加密与性能设置卡死问题的执行计划 (V2)

## 1. 现状分析
根据用户的反馈和对代码的探索，当前系统存在以下核心 Bug 和新需求：

**Bug 1: 导入加密文件夹后直接显示“完成”且未导入任何文件**
- **原因**：在 `vault_explorer_page.dart` 中，针对“导入文件夹”操作，在创建根任务时未将 `masterKey` 传入 `taskArgs`。这导致 `EncryptionTaskManager.pumpQueue` 在处理子文件任务时，因缺少 `masterKey` 瞬间将所有子任务标记为 `failed`。
- **原因**：`EncryptionTaskManager._parseTree` 解析目录树时丢失了子文件的本地路径 `path`，导致 `localPath` 为空，进一步触发失败。
- **原因**：`doImportFolderIsolate` 仅在虚拟文件系统中创建了根目录，未创建子目录。当 `LocalVfs.uploadStream` 尝试写入子目录中的文件时，会因父目录在磁盘上不存在而抛出异常。

**Bug 2: 在“性能设置”中拖动 CPU 数量滑块时应用卡死**
- **原因**：拖动滑块会频繁调用 `_persist` 并触发 `EncryptionTaskManager().pumpQueue()`。由于 Bug 1 中大量子任务因缺少参数而瞬间被判定为失败（且同步执行 `continue`），`pumpQueue` 的 `while` 循环在处理数百/数千个失败任务时，形成了 O(N^2) 复杂度的密集同步循环，完全阻塞了 UI 主线程（UI Thread），导致应用无响应。

**新需求 1: 加密任务与同步任务的历史记录分离**
- 当加密任务成功完成并校验所有文件均存在后，从任务队列移除并移入“加密历史记录”。
- 当云盘同步任务成功完成并校验达到要求后，从同步队列移除并移入“云盘同步历史目录”。

**新需求 2: 全新 UI 设计规范**
- 针对任务面板、历史记录面板、同步设置和性能设置等新引入的 UI，全面采用圆角设计，并使用类似 `Curves.elasticOut` 或 `Curves.spring` 的“QQ弹弹”动画效果，同时确保适配纯黑、亮色、赛博朋克三种主题。

## 2. 拟议更改与实现步骤

### 步骤 1: 修复加密任务隔离环境的参数缺失
- **文件**: `lib/encryption/vault_explorer_page.dart`
- **操作**: 在 `import_folder` 分支中，创建 `taskArgs` 时将 `masterKey` 加入其中。
- **文件**: `lib/encryption/services/encryption_task_manager.dart`
- **操作**: 修改 `_parseTree`，确保从 `treeMap` 解析子节点时保留 `path` 和 `remotePath` 并存入 `taskArgs`。

### 步骤 2: 修复死循环阻塞与文件目录创建逻辑
- **文件**: `lib/encryption/services/encryption_task_manager.dart`
- **操作**: 在 `pumpQueue` 的 `while` 循环中，若任务失败执行 `continue` 前，添加 `await Future.microtask(() {});` 释放事件循环。
- **文件**: `lib/vfs/local_vfs.dart`
- **操作**: 修改 `uploadStream`，在调用 `file.openWrite()` 之前检查并递归创建父目录。

### 步骤 3: 实现加密与同步的历史记录机制
- **加密历史**: 在 `EncryptionTaskManager` 中增加 `_historyTasks` 队列，保存至 `encryption_history.json`。任务 `done` 后，通过 `vfs.exists()` 或本地磁盘校验文件，全部存在则移入历史。
- **同步历史**: 在 `SyncStorageService` 中增加 `saveHistoryTasks` 和 `loadHistoryTasks`。在同步引擎完成同步并校验文件后，将其移入同步历史记录。

### 步骤 4: 重构弹性圆角 UI 界面
- **文件**: `lib/encryption/encryption_page.dart` (或其包含的 Progress Panel) 和 `lib/cloud_drive/cloud_drive_progress_panel.dart`
- **操作**: 为任务面板增加 `TabBar`（进行中 / 历史记录）。所有卡片和弹窗增加 `borderRadius`，切换和展开动画使用 `TweenAnimationBuilder` 配合 `Curves.elasticOut`，确保在赛博朋克主题下显示霓虹边框，纯黑主题下显示高对比度，亮色下显示阴影。

## 3. 假设与决策
- **决策**: 放弃在 `doImportFolderIsolate` 中递归创建虚拟目录，改为在最底层的 `LocalVfs` 写入数据时按需创建父目录，更健壮。
- **决策**: 历史记录采用独立的 JSON 文件存储（或 SharedPreferences 独立 key），防止任务队列文件过大导致加载缓慢。
- **假设**: 解决数据断层后，加密线程将进入真实多线程流。历史记录校验过程将采用异步不阻塞的方式进行，以免拖慢任务完成的响应速度。

## 4. 验证步骤
1. 编译并运行应用，进入加密空间。
2. 尝试导入包含子文件夹的文件夹，观察进度条正常走动，不再瞬间“完成”。
3. 验证加密成功后，任务自动从“进行中”消失，并带有 Q弹 动画进入“历史记录”页签。
4. 进入“性能设置”，快速拖动 CPU 滑块，验证应用是否保持流畅。
5. 测试云盘同步流程，确认同步完成后任务正确移入云盘同步历史目录。
6. 切换三种主题，确认历史记录和任务面板 UI 表现均正常且统一。