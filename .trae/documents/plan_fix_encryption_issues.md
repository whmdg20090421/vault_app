# 修复加密与UI相关问题计划 (Plan for Fixing Encryption & UI Issues)

## 1. 现状分析 (Current State Analysis)
- **问题 1：手动暂停与子任务恢复异常**
  目前在 `EncryptionTaskManager` 中，暂停文件夹时会将所有处于 `pending_waiting` 的子节点标记为 `pending_paused`。当用户在包含错误的文件夹上点击重试（或者使用 `markTaskAsFixed`）时，系统只重置了 `error` 状态的节点，而遗漏了 `pending_paused` 状态的节点，导致其无法恢复为黄色（进行中）并继续加密。此外，UI 中的重试/播放按钮在 `isError` 时被禁用，导致无法直观地一键恢复报错节点。
- **问题 2：加密时间过长 (性能瓶颈)**
  分析发现，目前的加密底层算法 `ChunkCrypto` 中的 `_encryptChunkSync` 和 `_decryptChunkSync` 是静态方法，对于每一个 64KB 的数据块，都会重新实例化 `pc.GCMBlockCipher(pc.AESEngine())`。这不仅导致海量对象的创建，还使得系统对每个 64KB 块都重复进行 AES 的密钥扩展（Key Schedule）操作。对于 30MB 的文件，这一操作会重复进行 480 次，极大地拖慢了加密速度。
- **问题 3：加密文件夹中无法通过长按删除**
  在 `VaultExplorerPage` 中，长按文件/文件夹弹出的菜单只有“多选”、“移动”和“复制”，缺少“删除”选项。

## 2. 拟定更改 (Proposed Changes)

### 2.1 修复暂停与错误恢复逻辑
**目标文件**: `lib/encryption/services/encryption_task_manager.dart` 和 `lib/encryption/widgets/encryption_progress_panel.dart`
- **更改**: 
  - 在 `EncryptionTaskManager.markTaskAsFixed` 中的 `fixRecursively` 方法内，不仅重置 `error` 状态，还要同时将 `pending_paused` 的节点重置为 `pending_waiting`，并设置 `n.isPaused = false`。
  - 在进度面板 UI 中，修改播放/暂停按钮的逻辑：当 `isError` 时不再禁用按钮，而是将其点击事件映射为 `markTaskAsFixed(task)`（重试），从而实现一键恢复执行。

### 2.2 优化 AES-GCM 算法性能
**目标文件**: `lib/encryption/utils/chunk_crypto.dart`
- **更改**: 
  - 将 `_encryptChunkSync` 和 `_decryptChunkSync` 从静态方法改为实例方法。
  - 在 `ChunkCrypto` 的构造函数中初始化并持有 `pc.GCMBlockCipher(pc.AESEngine())` 实例（如 `_encryptCipher` 和 `_decryptCipher`）。
  - 在加解密每个数据块时，直接调用现成实例的 `init()` 并处理数据，避免重复分配内存和实例化 AES 引擎。这将显著提升处理大文件时的加密效率。

### 2.3 添加长按删除功能
**目标文件**: `lib/encryption/vault_explorer_page.dart`
- **更改**: 
  - 在 `onLongPress` 弹出的 `showModalBottomSheet` 菜单中，添加一个 `ListTile`（图标：`Icons.delete`，颜色：红色，文字：“删除”）。
  - 点击后弹出二次确认框，确认后调用 `_vfs.delete(file.path)` 删除文件/文件夹，并调用 `_loadFiles()` 刷新列表。

## 3. 假设与决策 (Assumptions & Decisions)
- 假设目前的 64KB 分块大小在不重复实例化密码器的情况下已经能满足性能预期（Dart 运行时的纯 AES 性能极限），不更改块大小可以保持前向兼容。
- 决定直接复用进度条面板上的“播放/重试”按钮来处理错误节点的恢复，这符合用户操作直觉。

## 4. 验证步骤 (Verification Steps)
1. 运行应用，上传大文件并中途手动暂停文件夹，然后使某个子文件出错或保持暂停，点击播放按钮，确认所有子节点均能恢复为黄色（正在加密）。
2. 上传一个 30MB 的测试文件，测量加密耗时，验证其时间是否显著降低（期望从十几秒降至数秒内）。
3. 进入保险箱，长按一个文件夹，验证菜单中是否出现“删除”选项，且点击后能够正常删除该文件夹。