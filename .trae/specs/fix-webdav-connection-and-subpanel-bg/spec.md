# 修复 WebDAV 连接与子面板背景常驻 Spec

## Why
1. 目前 WebDAV 客户端无法连接到具体文件。需要修复连接问题，并通过本地测试确认能够收到 401 权限不足的响应（证明已能正常访问服务器）。同时，任何 WebDAV 相关的报错都需要写入到指定的 Android 路径 `/storage/emulated/0/Android/data/com.tianyanmczj.vault/files/webdav_error_log.txt` 中。
2. 开启自定义背景图片后，在底部导航栏切换时正常，但打开具体的子面板（如“关于”页面）时，背景会先重置为默认背景再重新显示，导致闪烁。需要让自定义背景常驻在底层，不因路由切换而重置。

## What Changes
- **WebDAV 连接修复**：排查并修复 WebDAV 针对具体文件的连接逻辑（如路径拼接、请求头等）。
- **WebDAV 错误日志**：实现日志记录机制，将 WebDAV 连接的报错信息写入 `/storage/emulated/0/Android/data/com.tianyanmczj.vault/files/webdav_error_log.txt`。
- **本地测试验证**：在本地运行代码尝试连接，验证是否成功返回 401 权限不足。
- **UI 背景常驻**：调整全局背景的层级或路由页面的背景色，确保在进入新路由（子面板）时，背景图片保持不动且不闪烁。

## Impact
- Affected specs: WebDAV 同步功能，UI 主题与背景设置。
- Affected code: WebDAV 网络层（如 `webdav_client_service.dart` 或相关文件），路由与页面层（如各子页面的 Scaffold 背景色），以及全局入口（`main.dart`）。

## ADDED Requirements
### Requirement: WebDAV 错误日志记录
系统必须将 WebDAV 相关的错误详情追加写入到指定的绝对路径文件中。

#### Scenario: 连接失败
- **WHEN** WebDAV 请求发生异常或失败时
- **THEN** 将错误信息写入 `/storage/emulated/0/Android/data/com.tianyanmczj.vault/files/webdav_error_log.txt`。

### Requirement: 本地连接验证
必须能在本地运行测试，确认目标 WebDAV 服务器返回 401 Unauthorized 错误，以证明网络连通性。

## MODIFIED Requirements
### Requirement: 全局背景常驻无闪烁
开启自定义背景后，该背景必须在整个应用生命周期中常驻最底层。进入任何子面板或新页面时，背景不能发生重置或闪烁现象。