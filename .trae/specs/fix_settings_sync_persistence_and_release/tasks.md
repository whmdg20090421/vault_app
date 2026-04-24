# Tasks

- [x] Task 1: 检查并解释应用如何判断本地与云端是否为同一文件（不依赖创建/上传时间）
  - [x] SubTask 1.1: 回顾并确认 `SyncEngine` 中 `PROPFIND` 参数解析逻辑（文件大小 `size` 与哈希 `eTag` 的比对），并向用户进行书面说明，确保不再依赖上传时间与本地创建时间造成重复同步。
- [x] Task 2: 将全局设置参数（主题、自定义背景、加密属性等）持久化到内部私有目录的 JSON 文件中
  - [x] SubTask 2.1: 创建或重构 `SettingsManager` (如 `lib/services/settings_manager.dart`)，支持将各项设置存为 JSON 文件（位于 `getApplicationDocumentsDirectory` 下）。
  - [x] SubTask 2.2: 在应用启动时（`main.dart` 或初始化的位置）调用该 Manager 从 JSON 加载设置并应用。
  - [x] SubTask 2.3: 在 `PerformanceSettingsPage`, `ThemeSettingsPage`, `SecuritySettingsPage` 等设置页面中，确保每次更改设置时同步调用 Manager 写入 JSON。
- [ ] Task 3: 修复重启应用后同步任务失效（进度条卡死、文件数据丢失）的问题
  - [ ] SubTask 3.1: 检查 `SyncTask` 和 `SyncFileItem` 的 `toJson` / `fromJson`，确保所有状态（如 `transferredBytes`, `totalBytes`, `speed` 等）都被正确序列化。
  - [ ] SubTask 3.2: 在 `CloudDriveProgressManager` 和 `SyncStorageService` 中，确保同步完成的任务被标记并从内存中移除，同时追加写入到历史记录的 JSON (`sync_history_key`) 中。
  - [ ] SubTask 3.3: 确保重启后读取活跃的 `SyncTask` 时，能够被“继续/恢复”按钮正确接管（需要获取 WebDAV 凭据再次启动 `syncEngine.sync()`），而不是仅仅停留在 `pending` 状态卡死。
- [ ] Task 4: 编译并发布为下一个小版本
  - [ ] SubTask 4.1: 更新 `pubspec.yaml` 和 `CHANGELOG.md`，记录本次修复。
  - [ ] SubTask 4.2: 按照 `Trae/rules.Md`，执行 `git commit`、打上 tag 并 `git push` 以触发 GitHub Actions 编译。
