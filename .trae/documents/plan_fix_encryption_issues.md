# 修复加密性能、基准测试与UI相关问题计划 (Plan for Encryption Performance, Benchmark & UI Issues)

## 1. 现状分析 (Current State Analysis)

根据您的最新反馈，我们在深入审查了底层的“硬件加密性能基准测试 (Benchmark)”模块后，确认存在严重的算法异常和逻辑漏洞：
1. **基准测试速度计算错误与吞没异常**：当使用第二种算法 (ChaCha20-Poly1305) 时，由于 `pointycastle` 库的内部异常，导致工作线程瞬间崩溃退出。但主线程未能捕获该错误，反而使用了硬编码的 `500.0 MB / 0.02s` 计算公式，从而得出“几万MB/s”的虚假惊人速度。
2. **AES-256 速度极慢**：在基准测试中使用 AES-256 加密 500MB 文件耗时超过 10 分钟。这证实了纯 Dart 软件实现（`pointycastle`）在处理密集 CPU 计算时的极大瓶颈，且单块重复初始化的开销进一步放大了该问题。
3. **真实文件加密的其它问题**：包括分块过小 (64KB) 且无自适应机制、内存深拷贝频繁等，这些同样是造成真实场景下加密慢的核心元凶。
4. **UI 遗留问题**：暂停后红色的报错文件无法恢复，以及长按无删除选项。

## 2. 拟定更改 (Proposed Changes)

我们将分模块、彻底地重构底层加密引擎并修复所有的关联业务：

### 任务 1：引入底层硬件加密库并替换算法
**目标文件**: `pubspec.yaml`, `lib/encryption/utils/chunk_crypto.dart`
- **更改**: 引入业内标准、支持调用底层操作系统接口的 `cryptography` 与 `cryptography_flutter` 库。
- **验证**: 使用其提供的 `AesGcm.with256bits()` 和 `Chacha20.poly1305Aead()` 替换原本的纯软件实现，确保 AES 与 ChaCha20 算法均能正确、稳定且高速地运行。

### 任务 2：修复并重构加密速度校验 (Benchmark) 模块
**目标文件**: `lib/encryption/vault_config_page.dart`
- **更改**: 
  - 彻底抛弃硬编码的 `500.0 / seconds` 计算方式，改用真实的 `(_doneBytes / 1024 / 1024) / seconds` 来计算速度。
  - 在 Worker 中捕获底层抛出的任何异常并回传主线程。如果发生崩溃，UI 会立即终止并标红显示具体的报错信息，而非显示“完成”。
  - 将 Benchmark 底层的测试算法一并替换为新引入的 `cryptography` 库引擎，从而得出移动端设备的真实硬件吞吐量（预期可达百兆/秒以上）。

### 任务 3：加密块自适应分类算法与配置持久化
**目标文件**: `lib/vfs/encrypted_vfs.dart`, `lib/encryption/services/vault_manifest_service.dart`
- **算法设计**: 真实文件加密前，根据文件大小动态分配块大小：
  - 小文件（< 1MB）：**64KB** 至 **256KB**。
  - 中等文件（1MB ~ 10MB）：**1MB**。
  - 大文件（> 10MB）：**1MB 至 5MB**。
- **配置持久化**: 将分配的 `chunkSize` 记录在保险箱的 `.vault_manifest` 配置文件中。并在密文文件头部写入魔数头，做到双重保险。
- **兼容层**: 解密时优先从配置读取；若无配置则读魔数；若都不是则判定为旧版 64KB，确保老文件 100% 兼容。

### 任务 4：消除重复初始化与内存频繁拷贝
**目标文件**: `lib/encryption/utils/chunk_crypto.dart`, `lib/vfs/encrypted_vfs.dart`
- **更改**: 
  - 仅在处理文件流开始时初始化一次 `SecretKey` 与加密算法实例。
  - 废弃 `buffer.addAll(chunk)`，改为预先分配固定大小的 `Uint8List(chunkSize)`，通过 `setRange` 写入数据，实现内存零拷贝，消除 GC 压力。

### 任务 5：UI 交互修复（暂停恢复与长按删除）
**目标文件**: `lib/encryption/services/encryption_task_manager.dart`, `lib/encryption/widgets/encryption_progress_panel.dart`, `lib/encryption/vault_explorer_page.dart`
- **更改**: 
  - 修复 `markTaskAsFixed` 重置 `pending_paused` 状态，并允许用户直接点击进度条的“播放”按钮一键恢复报错任务。
  - 在 `VaultExplorerPage` 的长按菜单中新增红色的“删除”按钮。

## 3. 验证步骤 (Verification Steps)
1. 再次进入配置页，运行 500MB 基准测试，分别选择 AES-256 和 ChaCha20。验证两者的速度计算均准确且不崩溃，且耗时大幅缩减至正常水平（数秒内完成）。
2. 上传大中小不同体积的文件，验证配置文件中正确地自适应分配了不同的分块大小。
3. 验证通过纯软件加密的旧文件依然可以无缝解锁与预览。
4. 验证暂停上传后的红色报错子任务，点击播放可顺利恢复为黄色加密状态。
5. 验证保险箱内部文件长按弹出删除菜单且可正常工作。