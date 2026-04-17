# WebDAV High-Performance Sync Library Spec

## Why
原有的 WebDAV 客户端存在结构混乱、与 UI 耦合、无法处理复杂的网络重试和认证拦截等问题。为了彻底解决网盘连接（尤其是国内 123pan、坚果云等）的各种报错（如 401 权限不足、DNS 拦截），并为后续的高效增量同步（Sync Engine）打下基础，我们需要参考成熟的 `webdav-js` 架构，使用 Dart、Dio 和 xml 包重新实现一个高性能、零侵入、Clean Architecture 分层的 Flutter WebDAV 核心库。

## What Changes
- **新建基础通信层 (WebDavClient)**：封装 Dio，拦截 Basic Auth 认证，捕获所有 HTTP 级别的错误（`DioException`）并转换为结构化的 `WebDavException`。
- **新建协议解析层 (WebDavParser)**：使用 `xml` 包对 WebDAV 特有的 `PROPFIND` multistatus XML 响应进行规范化解析。提取核心元数据：`href` (路径), `getcontentlength` (大小), `getetag` (指纹), `resourcetype` (目录/文件判断)。
- **新建业务逻辑层 (WebDavService)**：在 `WebDavClient` 的基础上封装面向对象的方法：`readDir`, `mkdir`, `upload`, `download`, `move`, `remove`。
- **新建增量同步引擎草案 (SyncEngine)**：在业务逻辑层之上，提供一个基于 `ETag` 和 `Last-Modified` 的差异化比对和并发下载的骨架，供 UI 层直接调用。
- **删除旧版零散代码**：由于我们已经移除了所有旧的内部网络代码（如 `webdav_client_service.dart` 和 `webdav/` 文件夹），本次规范仅涉及全新创建的核心库代码，且强制与业务 UI（如 `webdav_edit_page.dart` 等）解耦。

## Impact
- Affected specs: `webdav-e2ee-vfs`, `implement-cloud-sync-feature`
- Affected code:
  - `lib/cloud_drive/webdav_new/webdav_client.dart` (新增)
  - `lib/cloud_drive/webdav_new/webdav_parser.dart` (新增)
  - `lib/cloud_drive/webdav_new/webdav_service.dart` (新增)
  - `lib/cloud_drive/webdav_new/webdav_file.dart` (新增)
  - `lib/vfs/standard_vfs.dart` (对接新的 `WebDavService`)

## ADDED Requirements
### Requirement: 基础通信层 (WebDavClient)
系统 SHALL 封装一个统一的 `Dio` 实例，提供对 WebDAV 自定义方法（如 PROPFIND, MKCOL, MOVE）的调用，并自动在拦截器中注入 `Authorization: Basic` 请求头。

#### Scenario: 成功发起 PROPFIND
- **WHEN** 业务层调用 `WebDavService.readDir('/')`
- **THEN** 底层通信层将发起 `PROPFIND` 请求，并在头中自动添加 `Depth: 1` 和认证信息，成功返回 207 Multi-Status 响应。

### Requirement: 协议解析层 (WebDavParser)
系统 SHALL 使用 `package:xml` 将 207 响应解析为 `WebDavFile` 实体列表。需特别注意对 `href` 进行 `Uri.decodeFull`，因为服务器返回的路径可能是 URL 编码后的。

### Requirement: 高性能增量同步 (SyncEngine 建议)
系统 SHALL 提供一个基于文件元数据的同步逻辑。当执行文件夹同步时，比较本地和远程的 `Last-Modified` 或 `ETag`，仅当远程版本较新或不存在于本地时，才触发并发受限（例如 `Future.wait` 的分批）的下载任务，避免瞬间撑爆网络队列。

## MODIFIED Requirements
### Requirement: 虚拟文件系统挂载 (StandardVfs)
旧的 `StandardVfs` 由于缺乏依赖已瘫痪，现在 SHALL 被修改为依赖全新的 `WebDavService` 以恢复正常的云盘文件浏览功能。
