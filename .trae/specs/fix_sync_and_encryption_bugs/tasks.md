# Tasks
- [x] Task 1: 修复同步模式下拉弹窗的背景透明问题。
  - [x] SubTask 1.1: 定位 `lib/cloud_drive/sync_settings_dialog.dart` 或相关组件中的同步模式下拉选择器。
  - [x] SubTask 1.2: 添加 `dropdownColor` / `canvasColor` 属性，确保在深色/浅色主题下背景均为不透明的实体颜色。
- [x] Task 2: 修改本地与云端文件夹选择粒度，允许选择子文件夹。
  - [x] SubTask 2.1: 修改本地加密文件夹选择逻辑，使选择器能下钻到子目录。
  - [x] SubTask 2.2: 修改云端同步文件夹选择逻辑，使 WebDAV 浏览弹窗允许选择具体的远程子目录。
- [x] Task 3: 修复同步任务 401 Unauthorized 鉴权失败问题。
  - [x] SubTask 3.1: 检查 `lib/cloud_drive/webdav_new/webdav_client.dart` 及其拦截器，确认 `Authorization` 头（Basic auth）在所有请求（PROPFIND/PUT 等）中都已正确附加。
  - [x] SubTask 3.2: 如果缺少鉴权配置，将其修复并打印关键日志以便追踪。
- [x] Task 4: 追踪并验证加密核心逻辑，修复明文透传或“假加密”漏洞。
  - [x] SubTask 4.1: 审阅 `lib/encryption/vault_explorer_page.dart` 中的 `doImportFileIsolate` 以及 `lib/vfs/encrypted_vfs.dart` 中的 `uploadStream`。
  - [x] SubTask 4.2: 确认加密流 `_encryptStream` 确实在 `uploadStream` 中被消费和写入。如果有任何跳过加密直接调用的地方，修正它。

# Task Dependencies
- [Task 4] depends on [Task 3]
