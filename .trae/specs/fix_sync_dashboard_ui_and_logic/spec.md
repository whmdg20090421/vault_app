# Fix Sync Dashboard UI and Logic Spec

## Why
在现有的云盘同步功能中，由于同步引擎更新后未与 UI 进度面板（`CloudDriveProgressManager`）对接，导致用户点击“开始同步”后，进度指示器一直转圈，而全局同步列表中无任何任务显示，让用户误以为应用卡死。此外，用户希望将“云盘同步列表”的入口移至导航栏右上方，以提供更清晰的访问路径。

## What Changes
- **同步引擎与进度管理器对接**：
  - 在 `WebDAVStateManager.startSync` 中生成一个 `SyncTask` 并注册到 `CloudDriveProgressManager`。
  - 在 `webdav_new/sync_engine.dart` 中，将原有的闭包任务列表重构为包含 `SyncFileItem` 的 `_SyncJob` 列表。
  - 在同步执行过程中，实时更新 `SyncFileItem` 的状态（如 `syncing`、`completed`），并调用 `CloudDriveProgressManager.instance.updateTask` 触发 UI 刷新。
- **同步列表入口 UI 调整**：
  - 在 `lib/main.dart` 的 `AppBar` 的 `actions` 中，当处于“云盘” Tab 时，增加一个云盘同步任务的图标按钮，点击后打开同步面板。
  - 移除原先底部导航栏双击“云盘”呼出同步面板的设定。

## Impact
- Affected specs: 云盘同步任务跟踪、全局同步进度监控面板、导航栏 UI
- Affected code: `lib/cloud_drive/webdav_state_manager.dart`, `lib/cloud_drive/webdav_new/sync_engine.dart`, `lib/cloud_drive/cloud_drive_progress_manager.dart`, `lib/main.dart`

## ADDED Requirements
### Requirement: Real-time Cloud Sync Task Tracking
The system SHALL populate and track `SyncTask` and `SyncFileItem` objects when `SyncEngine.sync` executes.

#### Scenario: Success case
- **WHEN** user clicks "Start Sync"
- **THEN** a new sync task appears in the Cloud Drive Progress Panel, and its files' status updates in real time.

## MODIFIED Requirements
### Requirement: Cloud Sync Progress Entry Point
- **Visual**: The AppBar MUST display a Cloud Sync Progress icon in the top right when the user is on the Cloud Drive tab. Clicking it MUST open the `CloudDriveProgressPanel`.
- **Removed**: The bottom navigation bar double-tap action for opening the Cloud Drive Progress Panel SHALL be removed.