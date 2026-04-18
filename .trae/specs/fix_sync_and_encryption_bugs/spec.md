# 修复同步设置与加密验证 Bug Spec

## Why
在测试 1.4.1 版本的同步与加密功能时发现了以下四个关键 Bug：
1. 云端同步模式选择弹窗的背景板未正常显示，与底层元素重叠。
2. 云端同步文件夹选择功能受限，只能选择加密文件夹根目录或云盘根目录，无法选择具体的子文件夹。
3. 同步过程中出现 `DioException [bad response]: 401 Unauthorized` 错误，表明 WebDAV 鉴权或请求配置有误。
4. 加密逻辑可能存在漏洞（之前出现过未加密直接完成的情况），需要对导入文件的加密链路进行追踪验证，确保文件内容被真实加密输出。

## What Changes
- **同步模式选择 UI 修复**：为同步模式的下拉菜单/弹窗添加正确的 `backgroundColor` 或 `canvasColor`，确保在各主题下背景不透明。
- **文件夹选择范围放宽**：修改本地与云端文件夹选择器的逻辑，允许用户浏览并选择具体的子文件夹，而不仅限于根目录。
- **WebDAV 401 错误修复**：排查 `SyncEngine` 或相关网络请求的 Header，确保 `Authorization` 头（Basic Auth 凭证）被正确拼装和传递。
- **加密链路验证与修复**：检查 `EncryptedVfs.uploadStream` 及 `ChunkCrypto` 逻辑，追踪 `doImportFileIsolate` 中的文件流是否经过了实际的加密转换操作，修补任何可能导致明文透传或直接跳过的漏洞。

## Impact
- Affected specs: 云盘同步设置 UI、WebDAV 认证模块、文件选择器模块、核心加密传输链路。
- Affected code:
  - `lib/cloud_drive/sync_settings_dialog.dart` (UI 与选择器)
  - `lib/cloud_drive/webdav_new/sync_engine.dart` / `webdav_client.dart` (网络鉴权)
  - `lib/encryption/vault_explorer_page.dart` (导入任务)
  - `lib/vfs/encrypted_vfs.dart` (加密链路)

## MODIFIED Requirements
### Requirement: 同步设置 UI
- **WHEN** 用户点击云端同步模式选项
- **THEN** 弹出的选择列表应具有不透明的纯色背景，遮挡下层 UI 以防重叠。

### Requirement: 文件夹选择粒度
- **WHEN** 用户在同步设置中点击选择本地加密文件夹或云端同步文件夹
- **THEN** 文件选择器应允许进入子目录，并将最终选定的具体子目录路径返回保存。

### Requirement: WebDAV 同步鉴权
- **WHEN** App 启动后台同步任务访问 WebDAV 服务
- **THEN** 必须携带正确的认证凭证（如 Basic Auth），服务器应返回 20x 或 30x，而非 401 拦截。

### Requirement: 加密链路强制校验
- **WHEN** 导入明文文件至加密文件夹
- **THEN** 文件的底层流必须强制经过 `ChunkCrypto` 处理，输出的二进制数据应为不可直接读取的密文格式。
