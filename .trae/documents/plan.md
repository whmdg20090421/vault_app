# 天眼·艨艟战舰 修复计划 (Plan)

## 1. 总结 (Summary)
根据用户的反馈，本次计划将修复以下四个问题：
1. **打开 APK 等文件失败** (`java.io.IOException: Failed to load asset path...`)：由 Android 系统的权限隔离导致，`OpenFilex` 无法直接读取应用内部缓存目录中的文件给安装器使用。
2. **文件名过长导致加密失败** (`OS Error: File name too long, errno = 36`)：由于长文件名经过定长加密和 Base64Url 编码后膨胀，超出了底层文件系统（通常为 255 字节）的限制。
3. **点击交互逻辑优化**：用户期望点击文件夹时直接进入（无弹窗），点击文件时弹出“是否打开文件”的确认框。
4. **导入文件/恢复任务时路径错误**：之前重构引入任务管理器时，文件和文件夹导入的 `taskArgs` 中遗漏了 `currentPath` 参数，导致新任务及重启后恢复的任务会默认回退到根目录 `/`。

## 2. 现状分析 (Current State Analysis)
- **文件打开问题**：目前在 `vault_explorer_page.dart` 中，预览和分享文件时使用了 `getTemporaryDirectory()`，该目录位于应用的私有内部缓存中。Android 的 PackageInstaller 等外部应用没有权限读取该私有路径。
- **长文件名问题**：`EncryptedVfs._encryptName` 采用直接 AES 加密并转 Base64 的方式，没有长度截断机制。当原始文件名本身就较长（如几十个中文字符）时，密文极易突破 255 字节上限。
- **点击交互**：目前的 `_buildFileList` 中，对文件夹点击有 `showDialog`，对文件则是直接调用 `_previewFile(file)`，与用户期望刚好相反。
- **导入路径**：在 `vault_explorer_page.dart` 中调用的 `_importFile` 和 `_importFolder`，传递给 `EncryptionTaskManager` 的 `taskArgs` 缺少了 `'currentPath': _currentPath`。

## 3. 拟定更改 (Proposed Changes)

### 3.1 修复点击交互逻辑 (Vault Explorer)
- **文件**：`lib/encryption/vault_explorer_page.dart`
- **更改**：
  - 在 `ListView` 的 `onTap` 处理逻辑中，如果是文件夹 (`file.isDirectory`)，直接执行 `setState(() { _currentPath = file.path; }); _loadFiles();`。
  - 如果是文件，弹出 `AlertDialog` 询问“是否打开文件 [文件名]?”，用户点击“确定”后才调用 `_previewFile(file)`。

### 3.2 修复 APK/文件 打开失败 (Vault Explorer)
- **文件**：`lib/encryption/vault_explorer_page.dart`
- **更改**：
  - 修改 `_previewFile` 和 `_shareFile` 中获取临时目录的逻辑。在 Android 平台上，优先使用 `getExternalCacheDirectories().first`（外部缓存目录），该目录对其他应用（如安装器）具有更好的可读权限。
  - 保留 `getTemporaryDirectory()` 作为回退方案。

### 3.3 修复导入及恢复时路径跳回根目录 (Vault Explorer)
- **文件**：`lib/encryption/vault_explorer_page.dart`
- **更改**：
  - 在 `_importFile` 和 `_importFolder` 组装 `taskArgs` 时，补充加上 `'currentPath': _currentPath`。这样任务在加密服务中创建时就能读取到正确的目标目录。

### 3.4 修复加密文件名过长 (Encrypted VFS)
- **文件**：`lib/vfs/encrypted_vfs.dart`
- **更改**：
  - 引入 `package:crypto/crypto.dart`。
  - 修改 `_encryptName`：当加密并 Base64 编码后的文件名长度超过 200 个字符时，使用 SHA-256 对其进行哈希，并返回以 `LFN_` 开头的截断哈希值（如 `LFN_` + 32位Base64字符）。
  - 修改 `list` 方法：在解密目录下的文件列表时，如果发现文件名以 `LFN_` 开头，则遍历 `_manifestEntries` 中的虚拟路径配置，寻找对应父目录下能加密出该 `LFN_` 值的原始 `plainName` 进行还原。
  - 修改 `stat` 方法：由于调用 `stat` 时我们已经知晓 `virtualPath`，无需再反向解密密文名，直接从 `virtualPath` 提取 basename 作为解密后的文件名，提升性能并解决长文件名解析问题。

## 4. 假设与决策 (Assumptions & Decisions)
- **长文件名哈希映射**：为了不破坏现有架构，超长文件名的真实名字可以被现有已有的 `.vault_manifest` 映射完美恢复，因为清单在文件物理创建/上传前就已由 TaskManager 提前写入。
- **外部缓存目录安全性**：`getExternalCacheDirectories` 会在卸载应用时自动清除，并且其中的解密预览文件在查看后或延时（如10分钟）后会被立刻清理，符合安全规范。

## 5. 验证步骤 (Verification steps)
1. 编译应用后，进入任意深层目录导入一个长文件名的文件，观察是否能正常加密并且不报错，且正确留在当前目录。
2. 重启应用，观察中断的加密任务是否仍然处于原定目录。
3. 点击一个文件夹，验证是否无弹窗直接进入。
4. 点击一个文件，验证是否弹出确认框，确认后成功打开文件（尤其是 .apk 文件是否能成功唤起系统安装器）。