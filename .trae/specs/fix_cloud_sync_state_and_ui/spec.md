# Fix Cloud Sync State and UI Spec

## Why
目前在应用中，同步引擎和文件浏览器无法准确识别本地文件与云端文件是否为同一个文件，导致首页统计不准确，且已同步的文件仍显示为“未同步”。此外，在对云端文件进行并发的上传、下载或修改时，缺乏并发控制，可能导致数据冲突。点击开始同步后按钮会一直转圈直至重启应用，且同步进度缺乏速度和剩余时间的显示。

## What Changes
- 改进文件同一性判断逻辑：使用 WebDAV 的 `PROPFIND` 方法获取云端文件的详细参数（如 `getetag`, `getcontentlength`, `getlastmodified`），以此准确判断本地文件与云端文件是否一致。
- 引入并发控制机制：在对云端文件进行上传、下载、修改操作前，使用 WebDAV 的 `LOCK` 方法锁定文件；在操作完成后，使用 `UNLOCK` 释放锁定，防止并发写入导致冲突。
- 修改首页的刷新逻辑，基于上述改进的判断逻辑精确统计云端文件夹内的文件数量，以及真正存在差异的文件数量。
- 修复云端文件浏览器中“未同步”状态的判断逻辑，使其依赖于最新的 `PROPFIND` 校验结果。
- 修复点击“开始同步”后无限转圈的问题。调整为：点击后进行差异计算，计算完成后恢复按钮状态，并将任务推送到同步任务进度中。
- 在同步任务进度管理器中增加对传输速度（上传/下载）和预计剩余时间的计算和显示。

## Impact
- Affected specs: 同步引擎差异校验、WebDAV 网络请求层、云端文件浏览器状态显示、首页统计显示、同步进度详情显示。
- Affected code: `lib/cloud_drive/webdav_new/` (如 `webdav_client.dart`, `sync_engine.dart`)、`SyncSettingsDialog`、`CloudDriveProgressManager` 等。

## MODIFIED Requirements
### Requirement: 差异校验与同一性判断
- **WHEN** 同步引擎或界面需要判断文件状态时
- **THEN** 系统必须通过 `PROPFIND` 获取云端参数，并与本地索引/文件进行精准对比，确保“已同步”/“未同步”状态判断无误。

### Requirement: 并发控制 (Lock/Unlock)
- **WHEN** 系统准备上传、下载或修改云端文件时
- **THEN** 必须先发送 `LOCK` 请求锁定该文件，并在操作（成功或失败）结束后发送 `UNLOCK` 请求释放锁定。

### Requirement: 开始同步交互
- **WHEN** 用户在同步设置中点击“开始同步”
- **THEN** 系统开始计算差异文件，界面显示加载状态；计算完毕并将任务添加到进度队列后，加载状态结束，弹窗关闭。

### Requirement: 同步进度显示
- **WHEN** 用户查看同步进度详情
- **THEN** 界面上应显示当前任务的传输速度（如 KB/s 或 MB/s）和预计剩余时间。
