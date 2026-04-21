# Vault Legacy Encryption Upgrade Bug Fix & Re-encryption UI Plan

## Summary
修复在打开旧版加密保险箱时，点击升级选项（“继续使用”、“更新加密方式”、“重新加密”）无响应或闪退的 Bug。实现“更新并重新加密”功能，包括后台加密任务状态管理、全屏进度提示、防止误退出的二次警告，以及退回后台（保险箱列表）时的灵动岛胶囊状态栏。

## Current State Analysis
1. **Bug 分析**：
   在 `_showUnlockDialog` 中，当密码验证成功后，调用了 `Navigator.of(context).pop()` 关闭了解锁弹窗。此时弹窗的 `context` 已被销毁。紧接着如果需要升级（旧版本），会调用 `_askLegacyUpgradeChoice` 显示升级选项，并在选择后继续使用该已销毁的 `context` 调用 `Navigator.of(context).push` 或 `ScaffoldMessenger`，导致抛出异常被 catch 捕获，最终表现为弹窗直接关闭且未进入保险箱。
2. **选项逻辑分析**：
   - 选项1（继续使用）：应保持旧版配置直接进入。
   - 选项2（更新加密方式）：应调用 `_upgradeLegacyVaultNoReencrypt` 更新为V2配置结构，使用新KDF包裹旧DEK，然后进入。
   - 选项3（升级并重新加密）：应调用 `VaultKeyRotationService().rotateInPlace` 进行全量重新加密，目前该方法没有进度回调，且调用时会阻塞UI（无进度提示）。

## Proposed Changes

### 1. `lib/encryption/services/vault_key_rotation_service.dart`
- **What**: 增加全局任务状态管理，修改 `rotateInPlace` 以支持进度回调。
- **How**:
  - 声明全局变量 `final globalReencryptionTask = ValueNotifier<ReencryptionTaskState?>(null);`
  - 定义 `ReencryptionTaskState` 类，包含 `vaultPath`, `vaultName`, `processedBytes`, `totalBytes`, `isFinished`, `error` 字段。
  - 在 `rotateInPlace` 中，增加参数 `void Function(int processed, int total)? onProgress`。
  - 在正式拷贝前，先递归遍历 `oldEncryptedVfs` 计算所有文件的 `totalBytes`。
  - 在 `uploadStream` 之前，通过 `stream.map` 拦截数据流，累加 `processedBytes` 并触发 `onProgress` 回调。

### 2. `lib/encryption/encryption_page.dart` (解锁与升级逻辑修复)
- **What**: 修复 `context` 销毁导致的异常，实现选项逻辑与重加密弹窗触发。
- **How**:
  - 在 `_showUnlockDialog` 中，重命名内部弹窗 `context` 为 `dialogContext`。
  - 将 `Navigator.of(dialogContext).pop();` 延迟到异步校验和逻辑完成之后，或者在弹出后使用 `this.context` 进行后续的路由跳转和消息提示（需检查 `mounted`）。
  - 修改 `_askLegacyUpgradeChoice` 的选项文本，使其更明确：
    - `稍后再说` -> `继续使用旧版方式`
    - `立即升级` -> `仅更新配置`
    - `升级并重新加密` -> `更新并重新加密全库`
  - 对于选项3，当选择后，**不**立刻进入保险箱，而是调用 `_startReencryptionTask` 并立刻展示全屏进度提示。
  - 在 `_showUnlockDialog` 验证密码前，检查 `globalReencryptionTask.value?.vaultPath == item.path && globalReencryptionTask.value?.isFinished == false`，如果是，则提示“该保险箱正在重新加密中，请稍后再试”，拦截解锁。

### 3. `lib/encryption/encryption_page.dart` (全屏进度提示与二次警告)
- **What**: 实现全屏的重加密进度弹窗，并增加物理返回和隐藏后台时的二次警告。
- **How**:
  - 编写 `_showReencryptFullScreenDialog`，使用 `WillPopScope` 或 `PopScope` 拦截返回操作。
  - 触发返回或点击“隐藏到后台”按钮时，弹窗警告：“后台运行中如果App被系统清理，可能会导致未能被重新加密的文件永久丢失！确定要隐藏到后台吗？”
  - 若确认，则 `Navigator.pop` 关闭全屏弹窗，回到保险箱列表。

### 4. `lib/encryption/encryption_page.dart` (保险箱列表的灵动岛胶囊)
- **What**: 在保险箱列表顶部显示当前正在进行的重加密任务。
- **How**:
  - 在 `EncryptionPage` 的 `build` 方法中，主体 `_vaults` 列表外部包裹一层 `Stack`。
  - 使用 `ValueListenableBuilder<ReencryptionTaskState?>` 监听 `globalReencryptionTask`。
  - 若存在未完成的任务，在 `Stack` 顶部（`Positioned(top: 16)`）显示一个圆角胶囊容器，内部包含一个小的 `CircularProgressIndicator` 和任务名称及进度百分比。
  - 胶囊增加 `GestureDetector`，点击后重新打开全屏进度提示 `_showReencryptFullScreenDialog`。
  - 若任务完成 (`isFinished == true`)，胶囊显示“加密完成”，并提供一个关闭按钮来清空 `globalReencryptionTask.value`。

## Assumptions & Decisions
- 选项1和选项2的逻辑现有代码已基本实现，修复上下文销毁问题后即可正常工作。
- “隐藏到后台”的定义为“回到保险箱列表页（不退出App），并在列表顶部显示一个灵动岛胶囊提示进度”。
- 重新加密任务虽然是全局状态，但并未实现持久化（若App彻底被杀，则任务中断），这与现有架构和用户的“二次警告”提示内容相符。
- 采用 `ValueNotifier` 能够极其方便地在多个组件之间共享和刷新进度状态。

## Verification
1. 测试使用旧版保险箱：
   - 验证“继续使用旧版方式”能否正常进入并保留旧配置。
   - 验证“仅更新配置”能否成功更新并进入。
   - 验证“更新并重新加密全库”能否弹出全屏进度提示。
2. 测试全屏进度提示：
   - 验证物理返回和点击“隐藏到后台”能否触发二次警告。
   - 验证确认隐藏后，列表顶部是否出现灵动岛胶囊。
   - 验证点击灵动岛胶囊能否再次展开全屏进度提示。
   - 验证加密过程中再次点击该保险箱能否正确被拦截。