# 修复加密性能与UI相关问题计划 (Plan for Encryption Performance & UI Issues)

## 1. 现状分析 (Current State Analysis)

根据您的详细要求，我们对加密性能过慢的 5 个根本原因进行了深入剖析：
1. **未开启 AES 硬件加密加速**：目前应用完全依赖 `pointycastle`，该库无法调用移动端设备的硬件 AES 指令集。
2. **加密缓冲区过小**：目前分块大小硬编码为 `64KB`，对于 30MB 的大文件来说，分块多达 480 块，带来极大的 I/O 与加密调用的调度开销。
3. **单文件内重复初始化 Cipher 对象**：在 `ChunkCrypto._encryptChunkSync` 中，每个 64KB 的块都会重新 `pc.GCMBlockCipher(pc.AESEngine())` 并重新执行耗时的 AES 密钥扩展操作。
4. **流读写与内存拷贝过于频繁**：`EncryptedVfs.uploadStream` 使用了 `List<int> buffer` 配合 `addAll` 不断追加数据，触发了大量不必要的内存重分配与深拷贝。
5. **使用纯软件实现**：纯 Dart 实现的 AES 速度受限于 Dart 虚拟机，无法发挥操作系统的底层 C/C++ 加密库性能。

此外，UI 层面上还存在两个遗留问题：
- 手动暂停父文件夹后，个别报错的子文件无法一键恢复。
- 长按保险箱中的文件夹没有“删除”选项。

## 2. 拟定更改 (Proposed Changes)

我们将针对上述每一个问题创建对应的任务节点并进行修复：

### 任务 1 & 5：引入系统底层硬件加密库
**目标文件**: `pubspec.yaml`, `lib/encryption/utils/chunk_crypto.dart`
- **更改**: 引入业内标准的 `cryptography` 与 `cryptography_flutter` 依赖库。该库在 Android 上自动桥接 `javax.crypto.Cipher`，在 iOS 上桥接 `CommonCrypto`，能直接利用设备的硬件 AES 加速指令。
- **验证**: 我们将重写 `ChunkCrypto`，使用 `AesGcm.with256bits()` 进行加解密，并在隔离线程中调用，确保大文件加密速度得到质的飞跃且不崩溃。

### 任务 2：增大加密缓冲区并保持老文件兼容
**目标文件**: `lib/vfs/encrypted_vfs.dart`
- **更改**: 引入“魔数头”机制。新加密的文件头部将写入 6 字节魔数 `VAULT\x01`（标识 V1 大缓冲版），紧跟 16 字节 File ID，其分块大小提升至 **1MB**。
- **兼容层**: 解密时首先读取前 6 字节，若匹配 `VAULT\x01`，则以 1MB 缓冲流式解密；若不匹配，则判定为老文件（头部为 16 字节随机 File ID），自动回退使用 **64KB** 的老版本缓冲大小进行解密，确保您的历史数据 100% 安全可用。

### 任务 3：消除重复的 Cipher 与密钥初始化
**目标文件**: `lib/encryption/utils/chunk_crypto.dart`
- **更改**: 在处理单个文件流时，仅在开始前将 32 字节的主密钥包装为底层的 `SecretKey` 对象一次。后续的所有 1MB 分块都复用这个已经完成密钥扩展的 `SecretKey` 和统一的 `AesGcm` 实例，彻底消除每块重复初始化的开销。

### 任务 4：优化流读写与消除内存频繁拷贝
**目标文件**: `lib/vfs/encrypted_vfs.dart`
- **更改**: 废弃原有的 `buffer.addAll(chunk)` 做法。改为预先分配一个固定大小的 `Uint8List(1MB)` 或使用零拷贝的 `BytesBuilder(copy: false)`。通过维护游标 (offset) 将流数据直接写入固定内存区，满 1MB 后直接送入硬件加密层，极大降低 GC（垃圾回收）压力。

### 任务 6 & 7：UI 交互修复（暂停恢复与长按删除）
**目标文件**: `lib/encryption/services/encryption_task_manager.dart`, `lib/encryption/widgets/encryption_progress_panel.dart`, `lib/encryption/vault_explorer_page.dart`
- **更改**: 
  - 修复 `markTaskAsFixed`，确保同时重置 `pending_paused` 状态的子文件，并允许用户直接点击进度条的“播放”按钮恢复红色的报错任务。
  - 在 `VaultExplorerPage` 的长按菜单中新增红色的“删除”按钮，并对接现有的 `_vfs.delete` 删除逻辑。

## 3. 验证步骤 (Verification Steps)
1. 编译并运行，上传 30MB 的大文件，确认耗时从十几秒下降到 1~2 秒以内。
2. 尝试打开/预览以前用 64KB 纯软件加密的老文件，确保可以无缝解密查看（老文件兼容性测试）。
3. 暂停一个上传文件夹，手动使其子文件报错，点击播放按钮，确认可自动恢复为黄色（加密中）。
4. 在保险箱中长按文件夹，确认可直接点击删除。