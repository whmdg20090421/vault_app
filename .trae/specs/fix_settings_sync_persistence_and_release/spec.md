# Fix Settings Persistence, Sync Task Resumption, and CI Release

## Why
1. 同步同一性判断问题：应用需要精确识别本地与云端是否为同一个文件，不能单纯依赖上传时间与创建时间的比对，需要依赖稳定的属性（如文件大小、ETag/Hash）避免重复同步。
2. 设置项无法持久化：目前应用中的全局设置（如主题、自定义背景、加密参数等）每次重启后都会失效。需要将这些设置持久化到内部私有目录的 JSON 文件中。
3. 同步任务列表状态丢失：重启应用后，云盘同步任务进度条卡死失效，是因为任务及内部需要同步的文件数据只保存在内存中，重启后未被正确恢复并继续执行。需要将任务详情序列化至 JSON，同步完成后自动移入历史记录。
4. 版本发布：需要通过 GitHub Actions 编译并发布为下一个小版本。

## What Changes
- 深入检查并解释 `SyncEngine` 目前的同一性判断机制（已在上一版重构为基于大小和 ETag 的判断）。
- 新增 `SettingsManager` 或重构相关逻辑，将用户偏好设置（如背景、主题、加密选项）序列化到内部私有目录的 JSON 文件中，每次启动时读取，每次修改时写入。
- 修复 `SyncStorageService` 与 `CloudDriveProgressManager`：确保 `SyncTask`（特别是内部的 `items` 和 `transferredBytes` 等状态）在重启时被完整反序列化，并允许在重新启动应用后恢复断点任务；确保完成的任务正确移至历史记录 JSON 中。
- 遵循 `Trae/rules.Md`，执行代码提交、打标签并推送至 GitHub 触发 CI/CD 发布。

## Impact
- Affected specs: 设置持久化存储、同步进度恢复机制、版本发布流水线。
- Affected code: 
  - `lib/services/settings_manager.dart` (新建/修改)
  - `lib/settings/` (所有设置页面)
  - `lib/models/sync_task.dart` & `lib/cloud_drive/cloud_drive_progress_manager.dart`
  - `pubspec.yaml` & `CHANGELOG.md`

## MODIFIED Requirements
### Requirement: 设置项持久化
- **WHEN** 用户在设置页面修改了任何偏好设定（主题、背景、加密核心数等）
- **THEN** 应用将这些参数转换为 JSON 并写入内部私有数据目录；下次启动应用时自动读取并应用。

### Requirement: 同步任务持久化与恢复
- **WHEN** 用户重启应用并打开云盘同步进度面板
- **THEN** 应用从本地 JSON 读取未完成的同步任务（包含具体文件列表与进度），用户可以点击“恢复”继续同步，而不是卡死。
- **WHEN** 同步任务完成
- **THEN** 任务将被标记并从活跃队列移入同步历史记录的 JSON 文件中。
