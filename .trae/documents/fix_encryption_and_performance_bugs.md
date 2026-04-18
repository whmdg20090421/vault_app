# 修复多线程加密与性能设置卡死问题的执行计划

## 1. 现状分析
根据用户的反馈和对代码的探索，当前系统存在以下两个核心 Bug：

**Bug 1: 导入加密文件夹后直接显示“完成”且未导入任何文件**
- **原因**：在 `vault_explorer_page.dart` 中，针对“导入文件夹”操作，在创建根任务时未将 `masterKey` 传入 `taskArgs`。这导致 `EncryptionTaskManager.pumpQueue` 在处理子文件任务时，因缺少 `masterKey` 瞬间将所有子任务标记为 `failed`。
- **原因**：`EncryptionTaskManager._parseTree` 解析目录树时丢失了子文件的本地路径 `path`，导致 `localPath` 为空，进一步触发失败。
- **原因**：`doImportFolderIsolate` 仅在虚拟文件系统中创建了根目录，未创建子目录。当 `LocalVfs.uploadStream` 尝试写入子目录中的文件时，会因父目录在磁盘上不存在而抛出异常。

**Bug 2: 在“性能设置”中拖动 CPU 数量滑块时应用卡死**
- **原因**：拖动滑块会频繁调用 `_persist` 并触发 `EncryptionTaskManager().pumpQueue()`。由于 Bug 1 中大量子任务因缺少参数而瞬间被判定为失败（且同步执行 `continue`），`pumpQueue` 的 `while` 循环在处理数百/数千个失败任务时，形成了 O(N^2) 复杂度的密集同步循环，完全阻塞了 UI 主线程（UI Thread），导致应用无响应。

## 2. 拟议更改与实现步骤

### 步骤 1: 修复 `vault_explorer_page.dart` 中的参数缺失
- **文件**: `lib/encryption/vault_explorer_page.dart`
- **操作**: 在 `import_folder` 分支中，创建 `taskArgs` 之后，将 `masterKey` 添加进去：
  ```dart
  taskArgs['masterKey'] = widget.masterKey;
  ```

### 步骤 2: 修复 `EncryptionTaskManager` 中的树解析与死循环阻塞
- **文件**: `lib/encryption/services/encryption_task_manager.dart`
- **操作**:
  1. 修改 `_parseTree` 方法，确保从 `treeMap` 解析子节点时保留 `path` 属性并存入 `taskArgs`，以便后续文件加密可以获取到正确的 `localPath`。
  2. 在 `pumpQueue` 的 `while` 循环中，如果任务因缺少凭证或路径等原因被判定为失败并执行 `continue`，在其前面添加 `await Future.microtask(() {});` 释放事件循环，防止大量失败任务导致 UI 线程卡死。

### 步骤 3: 修复 `LocalVfs` 中的目录创建逻辑
- **文件**: `lib/vfs/local_vfs.dart`
- **操作**: 修改 `uploadStream` 方法。在调用 `file.openWrite()` 之前，检查其父目录是否存在，如果不存在则自动递归创建父目录：
  ```dart
  if (!await file.parent.exists()) {
    await file.parent.create(recursive: true);
  }
  ```

## 3. 假设与决策
- **决策**: 放弃在 `doImportFolderIsolate` 中繁琐地递归创建虚拟目录，改为在最底层的 `LocalVfs` 写入数据时按需创建父目录，这是一种更健壮且更符合文件系统操作标准的防御性编程做法。
- **假设**: 解决上述两个数据断层（`masterKey` 和 `path`）后，加密隔离线程将能正确获取参数并进入真正的多线程加密流，从而让进度显示功能按预期正常工作。

## 4. 验证步骤
1. 编译并运行应用，进入加密空间。
2. 尝试导入一个包含多个文件和子文件夹的文件夹，观察进度条是否正常走动且不再瞬间显示“完成”。
3. 检查加密空间内是否成功生成了对应的文件及目录结构。
4. 进入“性能设置”，快速拖动 CPU 数量滑块，观察应用是否能保持流畅响应且不再卡死。