# Fix Cloud Drive Picker Blank Screen Spec

## Why
用户反馈在“选择云盘同步文件夹”页面时是一片空白（如图 1），尽管在云盘主页面（文件浏览）能够正常看到文件（如图 2）。同时，用户要求如果出现报错（例如连接失败、解析失败），需要弹出一个带有红色背景框、白色错误代码文本的提示框（如图 3），而不是静默失败或仅仅显示空白页面。此外，所有的连接或代码报错必须写入到指定的错误日志文件中。

## What Changes
- 修改 `_CloudDrivePickerPage`（云盘同步文件夹选择列表）的数据加载逻辑，从过时的 `SharedPreferences` 迁移到 `WebDavConfigRepository().listConfigs()`，解决列表空白问题。
- 创建全局复用的 `showVfsErrorDialog`，严格复刻图 3 的 UI 样式（红色背景容器，白色等宽文本，底部“取消”按钮）。
- 废除同步配置中过时且存在 Bug 的 `VfsFolderPickerDialog`（对于 WebDAV），直接复用 `WebDavBrowserPage(isPickingFolder: true)`，从而完美沿用“文件浏览”的成熟逻辑，确保文件夹正常显示。
- 在 `_CloudDrivePickerPage` 和 `VfsFolderPickerDialog` 中增加错误捕获，发生异常时弹出 `showVfsErrorDialog`。
- 新增/复用日志写入工具，将报错信息追加写入 `/storage/emulated/0/Android/data/com.tianyanmczj.vault/files/webdav_error_log.txt`。

## Impact
- Affected specs: 云盘同步设置弹窗 (`sync_settings_dialog.dart`)、VFS 文件夹选择器 (`vfs_folder_picker_dialog.dart`)、WebDAV 文件浏览页 (`webdav_browser_page.dart`)
- Affected code: 
  - `lib/cloud_drive/sync_settings_dialog.dart`
  - `lib/widgets/vfs_folder_picker_dialog.dart`
  - `lib/widgets/error_dialog.dart` (新增)
  - `lib/utils/log_utils.dart` (新增/复用)

## ADDED Requirements
### Requirement: Standardized Error Dialog & Logging
The system SHALL provide a standardized error dialog for all WebDAV connection/parsing errors.
#### Scenario: WebDAV Connection Fails
- **WHEN** 用户点击一个配置好的云盘准备选择同步目录，但连接失败时
- **THEN** 系统弹出一个标题为“解析失败”（或相关错误），内容为红色背景框及白色报错信息的对话框，并提供“取消”按钮。
- **THEN** 系统将该错误追加记录到规定的 `webdav_error_log.txt` 中。

## MODIFIED Requirements
### Requirement: Cloud Drive Picker List
**Modified**: 同步页面的云盘配置列表必须通过 `WebDavConfigRepository` 进行加载，以保持与主云盘页面逻辑的绝对一致性，防止出现空白白板。
