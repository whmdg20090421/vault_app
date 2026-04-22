# Refactor Encryption Agent Checks Spec

## Why
需要确保加密底层接口（如 `cryptography` 库）被真实、稳定地落实，并且能够在应用层与加密层之间的解密映射过程中完美配合。同时，用户在 `VaultExplorerPage`（加密文件夹资源管理器）中长按需要“重命名”功能，并且在点击文件夹时，需要增加“是否打开文件夹”的二次确认，以确保打开时能正确将明文目录名映射回底层真实的加密文件名，避免系统找不到文件。此外，需要引入专门的子 Agent 对接口兼容性、参数传递和崩溃风险进行多轮检查。

## What Changes
- **底层库检查与验证**：编写测试脚本验证 `cryptography` 库在设备上的可用性。如果发现问题，执行 `flutter pub get` 等重新下载或切换兼容实现的修复操作，确保底层接口不仅是“代码占位”，而是真正可运行的。
- **添加长按重命名功能**：在 `VaultExplorerPage` 的文件/文件夹长按菜单中，新增“重命名”选项。点击后弹出对话框输入新名称，并调用底层的 `_vfs.rename()` 进行真实路径的重命名与映射更新。
- **添加打开文件夹确认**：在 `VaultExplorerPage` 点击文件夹时，弹出 `AlertDialog` 询问“是否打开文件夹？”。用户确认后，将当前路径更新为选中的文件夹虚拟路径，并调用 `_loadFiles()`。
- **解密映射强校验**：重点检查 `EncryptedVfs.getRealPath` 的实现，确保虚拟路径（明文）能够百分之百正确映射回真实的加密路径（密文），否则由于名称不匹配会导致找不到文件。
- **Agent 多轮代码审查**：修改完成后，启动独立的子 Agent 对所有涉及的接口兼容性、参数传递进行反复检查，确保无崩溃。

## Impact
- Affected specs: `VaultExplorerPage` 的 UI 交互，`EncryptedVfs` 的映射逻辑，`ChunkCrypto` 的底层调用。
- Affected code:
  - `lib/encryption/vault_explorer_page.dart`
  - `lib/vfs/encrypted_vfs.dart`
  - `lib/encryption/utils/chunk_crypto.dart`

## ADDED Requirements
### Requirement: Long-Press Rename
The system SHALL provide a "重命名" (Rename) option when long-pressing a file or folder in the vault explorer.
#### Scenario: Success case
- **WHEN** user long-presses a file/folder and selects "重命名"
- **THEN** a dialog prompts for the new name, and upon confirmation, the file/folder is renamed and the list refreshes.

### Requirement: Confirm Folder Open
The system SHALL prompt the user for confirmation before opening a directory in the vault explorer.
#### Scenario: Success case
- **WHEN** user taps on a directory
- **THEN** a dialog asks "是否打开文件夹？", and if the user selects yes, the system correctly maps the decrypted folder name to the encrypted real path and opens it.

## MODIFIED Requirements
### Requirement: Robust Underlying Encryption Interface
The system SHALL ensure the encryption backend (`cryptography`) is fully functional and not just a stub.
**Reason**: To prevent silent failures or fake speed calculations where encryption isn't actually happening.
**Migration**: Add initialization checks or unit tests during the build/runtime.

## REMOVED Requirements
None.
