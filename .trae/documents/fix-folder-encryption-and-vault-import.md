# 摘要
修复导入文件夹时触发的 Isolate Unsendable 崩溃问题，增加任务运行状态的自检与崩溃捕获机制（使错误能在 UI 上显示并暂停任务），同时增加导入已有保险箱（检测 `vault_config.json`）的机制，防止重新安装后数据丢失。

# 现状分析
1. **Isolate 启动崩溃问题**：
   在 `vault_explorer_page.dart` 中调用 `Isolate.run(() => doImportFolderIsolate(args))` 时，由于匿名闭包捕获了包含 `ReceivePort` 的本地词法环境，导致 Dart 抛出 `object is unsendable` 的严重异常。
2. **缺乏运行期崩溃捕获机制**：
   目前 `Isolate.run` 返回的 `Future` 并没有链式调用 `.catchError()`，导致如果在启动或运行中发生崩溃，主线程毫无察觉，任务一直卡在“加密中”（进度0%），并且没有错误信息反馈到 UI。
3. **重新安装无法读取原有配置的问题**：
   在 `encryption_page.dart` 的 `_pickFolderAndConfig` 方法中，用户选择文件夹后强制要求创建新的保险箱配置。如果该文件夹下已有 `vault_config.json`，会覆盖原参数导致文件彻底损坏。

# 提出的更改
## 1. 修复 Isolate Unsendable 闭包捕获问题 & 完善崩溃检测
- **文件**: `lib/encryption/vault_explorer_page.dart` & `lib/encryption/encryption_page.dart`
- **操作**:
  - 在文件顶部定义全局的独立启动函数（如 `spawnFolderImport` 和 `spawnFileImport`），从而彻底切断匿名闭包对本地上下文中不可发送对象（如 `ReceivePort`）的意外捕获。
  - 在所有调用 `Isolate.run` 的地方，增加 `.catchError((e)` 的链路。当捕获到任何 Isolate 崩溃或异常时，立即调用 `EncryptionTaskManager().updateTaskStatus(taskId, 'failed', error: e.toString())`，将错误抛出至任务面板，供用户查看并暂停。
  - 修复 `doImportFolderIsolate` 中发送 `tree` 消息时遗漏 `taskId` 的问题（这也会导致 UI 接收时崩溃）。

## 2. 增加已有保险箱配置检测与自动导入机制
- **文件**: `lib/encryption/encryption_page.dart`
- **操作**:
  - 修改 `_pickFolderAndConfig` 方法，在用户选择目录后检查 `File('$result/vault_config.json')`。
  - 若存在则直接将该路径写入 `SharedPreferences`，并通过 SnackBar 提示“已导入现有保险箱配置”，阻止跳转到新建配置页。

# 假设与决策
- **决策**：利用 `Isolate.run().catchError` 作为“自检”机制，因为 Dart Isolate 在发生 OOM 或底层错误时，`Isolate.run` 会自动终止并抛出异常，捕获这个异常即可完美实现任务的崩溃感知与错误展示。
- **决策**：提取全局 Isolate 启动器是解决 `unsendable` 报错的最优解，可保证多线程稳定创建。

# 验证步骤
1. **测试隔离区崩溃恢复**：导入一个文件夹，验证 `Isolate` 能否正常启动。如果中途发生任何 Dart 异常，任务卡片应变红并展示具体的错误日志。
2. **测试文件夹加密进度**：确认修复 `taskId` 后，进度条不再停留在 0%。
3. **测试已有保险箱导入**：选择旧保险箱目录，确认能无缝添加到列表而不被覆盖。