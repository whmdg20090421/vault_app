# UI and Sync Bugs Fix Spec

## Why
用户在使用应用时遇到了几个UI交互和逻辑问题：云端同步文件夹无法显示内容、导入明文文件时路径错误、加密文件夹长按缺少移动和复制功能、加密进度视图无法进入子文件夹查看进度，以及设置项位置不合理。修复这些问题能显著提升应用的用户体验和功能完整性。

## What Changes
- 修复云端同步文件夹选择器，确保正确列出并显示远端文件夹内容。
- 修正加密文件系统中导入明文文件的逻辑，确保文件被导入到当前浏览的层级而不是根目录。
- 在加密文件夹的长按上下文菜单中添加“移动”和“复制”按钮及对应逻辑。
- 优化加密进度条功能，支持点击文件夹进入子文件夹查看内部文件的加密进度。
- 将“每次启动自动刷新信息”设置项从设置导航栏移动到“性能设置”页面中。

## Impact
- Affected specs: 云端同步配置、加密文件浏览器、传输任务管理器、应用设置
- Affected code:
  - 云端文件夹选择相关 UI (如 `webdav_folder_picker.dart` 或类似文件)
  - 加密文件导入逻辑 (`vault_explorer_page.dart` 等)
  - 加密文件列表项长按菜单
  - 传输/加密进度管理 UI
  - 设置页面及性能设置页面 (`settings_page.dart` 等)

## ADDED Requirements
### Requirement: 文件夹长按菜单增加移动和复制
The system SHALL provide "Move" and "Copy" options when long-pressing an encrypted folder.

### Requirement: 加密进度支持层级下钻
The system SHALL allow users to tap on a folder in the encryption progress view to navigate into it and see the progress of its children.

## MODIFIED Requirements
### Requirement: 导入文件到当前目录
When a user imports a file while navigating inside a subfolder of an encrypted vault, the file MUST be placed in that specific subfolder, not the root.

### Requirement: 重新组织设置项
The "Auto-refresh on startup" setting MUST be located under "Performance Settings" rather than the main settings navigation bar.

### Requirement: 云端文件夹显示
The WebDAV folder selector MUST correctly fetch and display the subfolders of the remote cloud drive.
