# 任务列表
- [x] Task 1: 修复全局背景闪烁与黑屏问题
  - [x] SubTask 1.1: 确认并获取 `lib/main.dart`（包含 `MaterialApp.builder` 和 `_BackgroundShell` 的入口文件）。
  - [x] SubTask 1.2: 在 `MaterialApp.builder` 级别使用 `Stack` 进行全局挂载，在底层放置当前主题的 `scaffoldBackgroundColor` 作为兜底色。
  - [x] SubTask 1.3: 为自定义背景图片（`Image.file` 或 `Image.asset`）添加 `gaplessPlayback: true` 属性，解决重绘闪烁问题。
  - [x] SubTask 1.4: 确认并修改 `app_theme.dart` 或页面代码，确保上层所有 `Scaffold` 和遮罩/弹窗的背景色被正确设置为透明 `Colors.transparent`。

- [x] Task 2: 高性能 Flutter WebDAV 同步库开发
  - [x] SubTask 2.1: 新增基础通信层 `WebDavClient`（封装 `dio`，支持自定义 HTTP 方法和 Basic Auth，添加类似 `toastOnFailure` 的全局异常捕获逻辑）。
  - [x] SubTask 2.2: 新增协议解析层 `WebDavParser`（使用 `xml` 解析 multistatus，提取 `href`, `getcontentlength`, `getetag`, `resourcetype`）。
  - [x] SubTask 2.3: 新增业务逻辑层 `WebDavService`，实现核心方法：`list`, `upload`, `download`, `move`。
  - [x] SubTask 2.4: 设计并提供基于 ETag 对比的增量同步引擎核心思路（`SyncEngine` 方案）。
  - [x] SubTask 2.5: 编写带有完整注释和并发限制考量（`Future.wait`）的具体示例骨架。
