# Tasks

- [ ] Task 1: 修复性能测试下拉框透明与遮挡问题
  - [ ] SubTask 1.1: 在 `lib/encryption/vault_config_page.dart` 的 `_showBenchmarkDialog` 中，为 `DropdownButtonFormField` 添加 `dropdownColor: Theme.of(context).colorScheme.surface`。
  - [ ] SubTask 1.2: 调整 `isExpanded: true` 以防止文本溢出或遮挡。

- [ ] Task 2: 修复基准测试 AES-256-GCM 的慢速（启用硬件加速）
  - [ ] SubTask 2.1: 在 `_benchmarkEncryptWorker` 的参数中传递 `rootToken` (RootIsolateToken.instance)。
  - [ ] SubTask 2.2: 在 Isolate 内，如果使用 AES-256-GCM，调用 `BackgroundIsolateBinaryMessenger.ensureInitialized(rootToken)` 并执行 `FlutterCryptography.enable()`，从而启用硬件加速而非退回到纯 Dart 软件实现。

- [ ] Task 3: 提取并增强 VfsFolderPickerDialog（支持混显文件和文件夹）
  - [ ] SubTask 3.1: 将 `_VfsFolderPickerPage` 提取为公用组件 `VfsFolderPickerDialog` (新建文件 `lib/widgets/vfs_folder_picker_dialog.dart`)。
  - [ ] SubTask 3.2: 修改其 `list` 逻辑，不再只保留 `f.isDirectory`，而是展示全部，但在渲染 `ListView` 时，对于文件仅展示 Icon 和文字，将 `onTap` 设为 `null` (或 Toast 提示“请选择文件夹作为同步位置”)，并把文件排在文件夹下面。
  - [ ] SubTask 3.3: 替换 `sync_settings_dialog.dart` 和 `sync_config_page.dart` 中原有的私有选择器实现，修复云盘根目录全文件时空白的困扰。

- [ ] Task 4: 云盘文件浏览增加移动、复制、删除功能
  - [ ] SubTask 4.1: 在 `lib/cloud_drive/webdav_browser_page.dart` 中，为每个 `ListTile` 增加 `Trailing` (如 `PopupMenuButton`)。
  - [ ] SubTask 4.2: 提供【删除】按钮，点击确认后调用 `widget.service.remove(item.path)`。
  - [ ] SubTask 4.3: 提供【移动】与【复制】按钮，点击后弹出 `VfsFolderPickerDialog` 选取目标文件夹，选取后调用 `widget.service.move(src, dst)` 或 `widget.service.copy(src, dst)`，并在成功后刷新当前列表。

- [ ] Task 5: 修复连通性测试成功但同步一直转圈圈的致命性能 Bug 与路径死循环
  - [ ] SubTask 5.1: 在 `lib/cloud_drive/webdav_new/sync_engine.dart` 中修改 `_saveLocalIndex` 方法。传入 `localIndex` 参数，仅当物理文件的大小与修改时间变化时，才重新计算 `_calculateFileHash`，否则复用旧的 hash，大幅消除 IO 瓶颈。
  - [ ] SubTask 5.2: 修复 `_syncRecursiveDir` 中当 `localEntity` 是 `Directory` 且远端不存在时，在执行 `service.mkdir(remotePath)` 后，**必须增加对该目录的递归调用** (`subDirFutures.add(_syncRecursiveDir(remotePath, localEntityPath, ...))`)，以防止该新目录下所有文件被彻底遗漏且导致外层等待阻塞。
  - [ ] SubTask 5.3: 确保在 `sync()` 的开头，`remoteDir` 总是以 `/` 开头，避免在 `WebDavParser.parseMultiStatus` 中与 `relativePath` 比对失败，引发递归路径循环扫描导致假死。

# Task Dependencies
- [Task 1, 2] 关联性能测试模块。
- [Task 3] 是 [Task 4] 的前置依赖（需提取公用 Dialog 供复制移动功能使用）。
- [Task 5] 是独立修复引擎 Bug 的关键任务。