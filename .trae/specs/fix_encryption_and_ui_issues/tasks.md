# Tasks

- [x] Task 1: 修复文件名加密方式（LFN乱码与纯密钥加密）
  - [x] SubTask 1.1: 在 `lib/vfs/encrypted_vfs.dart` 中，实现 `_hexEncode` 和 `_hexDecode` 方法，替换掉 `Base64UrlUtils.encode/decode`。
  - [x] SubTask 1.2: 更新 `_encryptName` 和 `_decryptName`，支持使用 Hex 编码（为了向下兼容，`_decryptName` 需使用 try-catch 保留对旧版 Base64Url 的解码支持）。
  - [x] SubTask 1.3: 更新 `mkdir` 方法，在创建真实物理目录后，将虚拟路径记录到 `_manifestEntries` 中，确保空文件夹的长名称（LFN）能在 `list` 中被反向映射。

- [x] Task 2: 修复主页文件统计（差异数量、本地/云端数量无法刷新）
  - [x] SubTask 2.1: 在 `lib/encryption/services/local_index_service.dart` 中，重写 `getFileStatistics`。
  - [x] SubTask 2.2: 扫描本地 `vaultDirectoryPath` 获取真实加密文件列表（排除标记文件如 `.vault_manifest`, `local_index.json` 等）。
  - [x] SubTask 2.3: 读取 `local_index.json`（云端已同步的文件记录），将 `cloudEncryptedCount` 设置为其文件数。
  - [x] SubTask 2.4: 对比本地文件和 `local_index.json` 的修改时间与大小，计算新增、修改和删除的文件总数，赋值给 `diffCount`。

- [x] Task 3: 修复长按设置中的“关于”无反应
  - [x] SubTask 3.1: 在 `lib/main.dart`（`SettingsPage`）中，找到触发“关于”的 `GestureDetector`。
  - [x] SubTask 3.2: 将 `GestureDetector(onTapDown, onTapUp, onTapCancel)` 替换为 `Listener(onPointerDown, onPointerUp, onPointerCancel)`，以防止 `ScrollView` 拦截并取消长按事件。

- [x] Task 4: 修复文件解密预览报错 (SecretBoxAuthenticationError)
  - [x] SubTask 4.1: 在 `lib/vfs/encrypted_vfs.dart` 的 `open` 方法中，移除原先依赖 `_manifestEntries` 猜测文件版本（V1/V2）的逻辑。
  - [x] SubTask 4.2: 直接使用 `baseVfs.open` 读取文件的前 26 个字节，验证是否包含 `T_VAULT` 魔数，从而动态确定实际的 `headerLength` 和 `chunkSize`。
  - [x] SubTask 4.3: 根据确定的 `headerLength`，计算真实的 `cipherStart` 并传入 `_decryptStream`，避免由于跳过错误的头部字节长度导致 MAC 校验失败。

- [x] Task 5: 优化加密进度信息的硬件/普通加密指示灯 UI
  - [x] SubTask 5.1: 在 `lib/encryption/widgets/encryption_progress_panel.dart` 的 `_buildModeTag` 附近，修改当前单一状态显示的逻辑。
  - [x] SubTask 5.2: 改为固定显示一个 Row，包含“硬件加密”和“普通加密”两个标签。
  - [x] SubTask 5.3: 根据任务当前的 `encryptionMode`（`hardware` 或 `software`），动态调整标签的颜色透明度，模拟指示灯的亮起和熄灭。

# Task Dependencies
- [Task 1, 2, 3, 4, 5] 均为独立修复任务，可以并行处理。
