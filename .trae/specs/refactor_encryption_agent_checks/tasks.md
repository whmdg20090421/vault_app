# Tasks

- [x] Task 1: 验证并落实加密底层库 (`cryptography`) 的可用性。
  - [x] SubTask 1.1: 编写独立的 Dart 验证脚本 (`test_crypto_impl.dart`)，导入 `cryptography` 并执行完整的 AES-GCM 和 ChaCha20 加解密测试，确保不崩溃。
  - [x] SubTask 1.2: 如果存在问题，清理缓存并重新执行 `flutter pub get`；或者修改 `ChunkCrypto`，以确保底层实现真实有效。
- [x] Task 2: 在 `VaultExplorerPage` 中添加长按“重命名”功能。
  - [x] SubTask 2.1: 在长按弹出的 `ModalBottomSheet` 菜单中增加一个 `ListTile`，图标为 `edit`，标题为“重命名”。
  - [x] SubTask 2.2: 实现点击重命名后的 `AlertDialog` 输入框。
  - [x] SubTask 2.3: 调用 `_vfs.rename`，传递正确的虚拟路径，完成重命名后调用 `_loadFiles()` 刷新列表。
- [x] Task 3: 在 `VaultExplorerPage` 中添加“是否打开文件夹”确认弹窗。
  - [x] SubTask 3.1: 修改文件夹的 `onTap` 事件，在 `file.isDirectory` 为 true 时，不直接更新 `_currentPath`，而是先弹出一个 `AlertDialog`。
  - [x] SubTask 3.2: 弹窗标题为“打开文件夹”，内容为“是否打开文件夹 {文件夹名称}?”，包含取消和确定按钮。
  - [x] SubTask 3.3: 确认打开后，执行 `_currentPath = file.path; _loadFiles();`。
- [x] Task 4: 反复检查加密层到应用层的解密映射过程（Agent Check）。
  - [x] SubTask 4.1: 创建一个独立的 Agent（使用 Task 工具），对 `EncryptedVfs.list`、`getRealPath`、`_encryptName` 和 `rename` 的调用关系进行代码逻辑审查。
  - [x] SubTask 4.2: 确保 `_currentPath`（明文路径）在传入 `_vfs.list` 时能够通过 `getRealPath` 缓存准确找回真实的加密目录名，避免出现找不到文件的问题。
  - [x] SubTask 4.3: 检查所有修改的接口的参数传递、返回值，确保无崩溃风险。

# Task Dependencies
- [Task 2] depends on [Task 1]
- [Task 3] depends on [Task 2]
- [Task 4] depends on [Task 3]
