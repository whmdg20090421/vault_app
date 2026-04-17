# Tasks

- [ ] Task 1: 修复版本号同步问题
  - [ ] SubTask 1.1: 检查并修改 `android/app/build.gradle.kts`，确保它从 `pubspec.yaml` 读取 `versionName` 和 `versionCode`，或者移除硬编码的 `version.properties` 逻辑，依赖 Flutter 默认的构建注入。
  - [ ] SubTask 1.2: 验证打包出来的 APK 版本号是否与 `pubspec.yaml` 一致。

- [ ] Task 2: 重构 WebDAV 客户端逻辑
  - [ ] SubTask 2.1: 废弃 `lib/cloud_drive/webdav_client_service.dart` 中原有的请求逻辑。
  - [ ] SubTask 2.2: 使用 `webdav_client` 库或重新配置 `dio` 客户端，修复 DNS 解析失败的问题。
  - [ ] SubTask 2.3: 实现核心操作（读取目录、创建目录、上传、下载、删除），并增加详尽的网络异常捕获。

- [ ] Task 3: 修复加密进度条不更新问题
  - [ ] SubTask 3.1: 检查 `vault_explorer_page.dart` 中的 `doImportFileIsolate` 和 `doImportFolderIsolate`，确保在文件流处理中正确通过 `sendPort` 发送进度事件。
  - [ ] SubTask 3.2: 检查 `EncryptionTaskManager` 中的 `updateTaskProgress` 逻辑，确保它不仅更新自身状态，还能正确触发树形结构中父节点的状态更新并 `notifyListeners()`。
  - [ ] SubTask 3.3: 修复 UI 层进度面板，确保它监听了 `EncryptionTaskManager` 的变化并重绘进度条。

# Task Dependencies
- [Task 1]、[Task 2]、[Task 3] 可并行开发，无强依赖。