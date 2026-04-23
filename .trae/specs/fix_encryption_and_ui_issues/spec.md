# Fix Encryption and UI Issues Spec

## Why
用户反馈了5个不同的问题：
1. 文件名过长时加密名称显示为 `LFN_` 乱码，且希望加密方式改为纯密钥加密（不使用 Base64/URL 编码）。
2. 主页的差异文件数量、云端/本地加密文件数量点击刷新后不更新。
3. 设置页的“关于”长按5秒进入开发者模式无响应（因为在滚动列表中容易被取消）。
4. 打开部分文件时出现 `SecretBoxAuthenticationError` MAC 校验失败的报错（由于 V1/V2 格式文件头长度判断不准导致）。
5. 加密进度面板的硬件加密与普通加密标签位置不固定，期望像指示灯一样固定显示并高亮。

为了提升用户体验和系统稳定性，我们需要修复这些 UI 交互和底层加密的逻辑缺陷。

## What Changes
- **文件名编码方式**：将 `EncryptedVfs` 中的文件名编码从 Base64Url 改为 Hex 编码（纯十六进制字符）。
- **LFN 空目录映射**：在 `EncryptedVfs.mkdir` 创建目录时，自动将新建目录的元数据保存到 `_manifestEntries` 中，确保超长文件名（`LFN_`）空目录在 `list` 时能够被正确逆向映射并显示原名。
- **文件统计逻辑**：修改 `LocalIndexService.getFileStatistics`，通过对比本地实际物理文件和 `local_index.json`（最后一次云端同步状态），动态计算 `localEncryptedCount`、`cloudEncryptedCount` 和 `diffCount`。
- **关于长按手势**：将 `SettingsPage` 中的“关于”按钮的长按手势从 `GestureDetector` 改为更底层的 `Listener`，防止因轻微滑动导致手势被 `ScrollView` 取消。
- **文件格式自动识别**：在 `EncryptedVfs.open` 中，直接从文件流的前 26 字节读取 `T_VAULT` 魔数，通过真实的物理文件头准确判断是 V1 还是 V2 格式，避免因读取错误的 headerLength 导致密文偏移错位和 MAC 报错。
- **加密指示灯 UI**：在 `EncryptionProgressPanel` 中，将当前的单标签显示改为固定的双指示灯（左：硬件加密，右：普通加密），并根据任务当前的 `encryptionMode` 状态切换高亮/熄灭状态。

## Impact
- Affected specs: 加密文件名生成逻辑、加密文件预览、主页数据统计刷新、设置页彩蛋手势、加密进度 UI。
- Affected code:
  - `lib/vfs/encrypted_vfs.dart`
  - `lib/encryption/services/local_index_service.dart`
  - `lib/main.dart`
  - `lib/encryption/widgets/encryption_progress_panel.dart`

## MODIFIED Requirements
### Requirement: Encrypted File Naming
The system SHALL encode AES ciphertext of filenames using Hexadecimal format instead of Base64Url. When the ciphertext exceeds 200 characters, it SHALL be truncated and hashed with SHA-256 (prefix `LFN_`). Empty directories MUST be saved to the manifest to allow reverse mapping of LFN paths.

### Requirement: Statistics Calculation
The system SHALL accurately calculate local/cloud/diff file counts by comparing actual physical files in the vault with the latest `local_index.json`.

### Requirement: Developer Mode Easter Egg
The system SHALL trigger the Developer Mode warning strictly after a 5-second continuous press on the "About" button in the Settings page, unaffected by scroll gestures.

### Requirement: File Decryption Robustness
The system SHALL reliably determine the encrypted file header length (16 bytes for V1, 26 bytes for V2) by reading the file's magic bytes directly, preventing stream offset mismatch.

### Requirement: Encryption Progress Indicators
The system SHALL display fixed-position "Hardware Encryption" and "Software Encryption" indicators for each active task, dynamically highlighting the active mode.
