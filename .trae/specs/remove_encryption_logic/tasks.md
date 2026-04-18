# Tasks
- [ ] Task 1: 备份并确认加密算法和 UI 的完整性。
  - [ ] SubTask 1.1: 确认 `lib/encryption/crypto/` 下的算法文件（如 `chunk_crypto.dart` 等）未受影响。
  - [ ] SubTask 1.2: 确认 `lib/encryption/encryption_page.dart` 及相关 UI 界面未受影响。
- [ ] Task 2: 清除或清空 `lib/encryption/services/encryption_task_manager.dart` 中的具体调度和业务逻辑。
  - [ ] SubTask 2.1: 保留必要的类定义（如 `EncryptionTaskManager`）和单例结构，删除其中的任务队列管理、多线程处理及执行逻辑，仅保留空方法以保持编译。
- [ ] Task 3: 清除或清空 `lib/vfs/encrypted_vfs.dart` 中的加密读写逻辑。
  - [ ] SubTask 3.1: 将 `uploadStream`, `downloadStream` 等核心方法的内部实现清空或抛出 `UnimplementedError`。
- [ ] Task 4: 移除 `lib/encryption/vault_explorer_page.dart` 及其他 UI 页面中发起具体加密流程的代码。
  - [ ] SubTask 4.1: 移除或清空 `doImportFileIsolate`, `_importFolder` 等方法内部调用底层逻辑的实现。
- [ ] Task 5: 验证并提交修改。
  - [ ] SubTask 5.1: 运行 `flutter analyze`，确保尽管清除了逻辑，但项目依然能够通过编译并且没有语法错误。
  - [ ] SubTask 5.2: 按照要求使用 `git-commit` 和 `gh-cli`，提交重构准备工作。

# Task Dependencies
- [Task 2], [Task 3], [Task 4] 可以并行。
- [Task 5] depends on [Task 2], [Task 3], [Task 4].
