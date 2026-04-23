# Performance UI and Cloud Sync Spec

## Why
用户反馈了5个不同的问题：
1. 性能测试中算法下拉框被遮挡且背景透明。
2. 在500MB性能测试中，AES-256-GCM 算法速度仅为 22MB/s，远低于 ChaCha20-Poly1305（50MB/s），由于测试时使用的是纯 Dart 软件实现而不是 FlutterCryptography 的硬件加速。
3. 云盘同步设置中无法看到文件（导致如果没有文件夹的云盘目录显示为空白），用户以为无法选择文件作为同步对象。
4. 云盘文件浏览器中缺少移动、复制和删除文件的功能。
5. 连通性测试成功，但点击同步后一直“转圈圈”无法完成同步（由于同步引擎在扫描文件和计算哈希时存在严重的性能瓶颈与目录递归遗漏导致的假死）。

## What Changes
- **Performance UI**: 修复 `VaultConfigPage` 中基准测试的 `DropdownButtonFormField` 样式，设置 `dropdownColor` 并在弹出层前添加必要的背景填充。
- **Benchmark Acceleration**: 优化 `_benchmarkEncryptWorker` 中创建 Cipher 的逻辑，不再在 Isolate 内使用纯 Dart 软件加密进行基准测试，而是支持（或提醒）硬件加速测试（AES-GCM 需要使用 `FlutterCryptography` 并在主线程或带 RootIsolateToken 的隔离区执行）。
- **Folder Picker Visibility**: 提取并重构 `_VfsFolderPickerPage` 为公用的 `VfsFolderPickerDialog`。在选择文件夹时，同时展示文件（不可点击进入），解决纯文件目录下显示“空白”的困惑。
- **Cloud File Operations**: 在 `WebDavBrowserPage` 的列表项中添加 `PopupMenuButton`，提供【移动】、【复制】、【删除】功能。移动/复制时弹出 `VfsFolderPickerDialog` 选择目标路径。
- **Sync Engine Optimization**: 
  - 在 `sync_engine.dart` 中，大幅优化 `_saveLocalIndex` 逻辑，仅对大小或修改时间发生变化的本地文件重新计算 SHA-256 哈希，跳过未修改文件的耗时哈希计算。
  - 修复 `_syncRecursiveDir` 中当本地存在新目录时，仅调用 `mkdir` 而没有递归进入该目录同步其内部文件的致命 Bug。
  - 确保 WebDAV 目录路径比较时统一带有前导 `/`，防止 `_isSamePath` 失败导致的重复请求和假死。

## Impact
- Affected specs: 基准测试UI与测速、文件夹选择器、云盘浏览器操作、云盘同步引擎
- Affected code:
  - `lib/encryption/vault_config_page.dart`
  - `lib/cloud_drive/sync_settings_dialog.dart` (及抽离的公用 Picker)
  - `lib/cloud_drive/webdav_browser_page.dart`
  - `lib/cloud_drive/webdav_new/sync_engine.dart`

## ADDED Requirements
### Requirement: Cloud Drive File Management
The system SHALL provide Move, Copy, and Delete actions for files and folders in the Cloud Drive Browser using WebDAV methods.

### Requirement: Mixed File/Folder Visibility in Picker
The system SHALL display files (as disabled/non-navigable items) alongside folders in the Sync Folder Picker to provide context and prevent blank screens.

## MODIFIED Requirements
### Requirement: Benchmark Hardware Acceleration
The benchmark test SHALL accurately reflect hardware-accelerated speeds for AES-256-GCM if enabled, avoiding fallback to slow software implementations in isolates.

### Requirement: Sync Engine Performance & Correctness
The Sync Engine SHALL incrementally calculate local file hashes (skipping unchanged files) and correctly recurse into newly created local directories during WebDAV synchronization.
