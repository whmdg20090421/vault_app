# 版本 1.3.4 (2026-04-17)

### ✨ Features
- **Resume Encryption**: 实现了后台加密队列的保存、重启恢复与断点续传功能。

# 版本 1.3.3 (2026-04-17)

### 🐛 Bug Fixes & Diagnostics
- **WebDAV Path Resolution**: 彻底修复 `WebDavParser` 导致服务器返回的绝对路径（`href`）与相对请求路径不匹配，从而使根目录无法正确过滤、产生额外 `webdav` 文件夹并造成 `404 Not Found` 的严重问题。
- **Enhanced Error Logging**: 大幅增强 `WebDavErrorLoggerInterceptor`，在异常发生时，将完整且详细的请求头（Headers）、请求方法（Method）、请求体（Data）以及完整的响应头（Response Headers）和响应体记录至日志中，便于深度排查服务端参数问题。

# 版本 1.3.2 (2026-04-17)

### ✨ Architecture & WebDAV Refactor
- 彻底重构 WebDAV 核心通信库：基于 Clean Architecture，拆分为 `WebDavClient`、`WebDavParser`、`WebDavService` 三层。
- 新增 `WebDavErrorLoggerInterceptor` 全流程拦截器：精确捕获并区分 `SocketException` (DNS失败)、`TlsException`、`HttpException`，将所有底层报错上下文完整写入 `/storage/emulated/0/Android/data/com.tianyanmczj.vault/files/webdav_error_log.txt`。
- 新增 `SyncEngine`：提供基于 ETag/Last-Modified 与 `Future.wait` 并发控制的高性能双向增量同步草案。
- 将应用 UI（WebDAV配置页、云盘浏览页）与 `StandardVfs` 重新对接至全新的 `WebDavService`。

# 版本 1.3.1 (2026-04-17)

### 🐛 Bug Fixes & Network
- 恢复 Android 默认 `flutter.compileSdkVersion` 配置，修复因强制指定 SDK 版本 34 导致的构建冲突。
- 提供基于 `dart:io` 原生 Socket 与 NetworkInterface 的终极网络诊断脚本。
- 新增 `network_security_config.xml` 配置信任系统/用户证书。

# 版本 1.3.0 (2026-04-17)

### ✨ Features & Bug Fixes
- **WebDAV 网络诊断**：在添加网盘页面新增“模拟网络连接”功能，用于主动测试设备的互联网连通性，排查 DNS 与网络权限拦截问题。
- **强制连接校验**：WebDAV 配置页面现在强制要求通过“测试/连接”校验后才允许保存。
- **底层加密引擎修复**：重构 `EncryptedVfs`，修复了当关闭“加密文件名”时，导入文件夹导致文件内容也完全不被加密且进度条卡死的严重漏洞。
- **同步进度快捷入口**：在加密文件夹内部（VaultExplorerPage）的右上角新增了同步进度快捷查看按钮。
- **UI 精简**：暂时去除了 WebDAV 浏览页面中复杂的高级功能（如上传、删除、重命名），仅保留纯净的目录展示以防止误操作。

# 版本 1.2.9 (2026-04-17)

### 🧩 UI & WebDAV
- 修复 WebDAV 客户端在连接和加载目录时抛出 `Unknown Dio error (Status: null)` 的问题。
- 修复了 WebDAV 具体文件的连接逻辑，成功解决因路径构造和拦截器导致的连接失败。
- 新增全局 WebDAV 错误日志记录机制，便于将报错详情输出到本地供调试排查。
- 彻底解决开启全局自定义背景时，导航进入子面板（如“关于”页面）造成的背景闪烁与重置问题（修改所有页面路由的过渡动画与纯色底色）。

# 版本 1.2.8 (2026-04-17)

### 🧩 UI & WebDAV
- 修复全局自定义背景在路由/重绘时的闪烁问题（图片层启用 gaplessPlayback，背景层稳定挂载）。
- 修复关闭背景图时因 Scaffold 透明导致的黑屏问题（增加全局兜底底色）。
- WebDAV 模块重构为 dio + xml 分层实现（Client/Parser/Service），移除对第三方 webdav_client 的依赖，并提供基于 ETag 的增量同步骨架。


# 版本 1.2.7 (2026-04-17)

### 🧩 UI & Bug Fixes
- 修复当关闭自定义背景时导致 UI 黑屏的问题，恢复主题默认背景。
- 补充 WebDAV 原生网络连接与测试文档说明，证明底层网络连接健康。


# 版本 1.2.6 (2026-04-17)

### 🧩 UI & Release Automation
- 修复弹窗 / 底部面板 / 页面跳转时的背景闪回默认底色问题，背景层保持稳定无闪烁。
- 新增发布准备脚本与 CI gate：构建/发布前自动校验版本一致性，并生成 README 版本摘要与 Release notes。

# 版本 1.2.5 (2026-04-17)

### 🔒 Security & Performance
- 修复 WebDAV 连接与错误提示的稳定性问题，并增强网络错误可读性（如 DNS 解析失败）。
- 修复大文件加密/导入时进度条不更新与潜在卡顿问题，进度上报节流以提升 UI 流畅度。

# 版本 1.2.4 (2026-04-17)

### 🔒 Security & Performance
- 修复加密任务管理器的结构性代码问题，避免运行期异常与进度面板失效。
- WebDAV 错误日志写入时对潜在敏感字段进行脱敏处理，并限制日志数量，避免长时间运行导致内存膨胀。
- 预览/分享临时解密文件改为可回收策略：页面销毁时回收，预览目录延迟清理。
- 自定义背景图片持久化存储到内部私有目录并清理旧背景文件，避免存储泄漏。

# 版本 1.2.3 (2026-04-16)

### ✨ Features & WebDAV Dashboard
- **WebDAV 仪表盘中枢**：引入专业的同步管理仪表盘（Dashboard），包含概览、动态日志和文件浏览三大板块，彻底告别空壳 UI。
- **全局状态管理**：新增 `WebDAVStateManager`，在仪表盘各 Tab 间共享最后同步时间、同步状态、活动日志等数据。
- **真实网络与同步逻辑**：使用原生网络库复刻 WebDAV 协议（PROPFIND/DELETE），接入真实的删除逻辑与差异比对（Diffing）同步引擎。
- **文件大小智能换算**：新增 `formatBytes` 工具，自动换算 KB/MB/GB 并在所有文件列表中应用。
- **缓存与无用文件清理**：清理了旧版冗余的缓存目录与空文件夹，使项目结构更加清爽。

# 版本 1.2.2 (2026-04-16)

### 🐛 Bug Fixes & Stability
- 修复部分设备上切换主题时的闪退问题。
- 优化了后台任务的内存占用，提升应用整体稳定性。

# 版本 1.2.1 (2026-04-16)

### ✨ UI Enhancements
- 优化了设置页面的排版与图标对齐。
- 增加了动画过渡效果，使交互更加流畅。

# 版本 1.2.0 (2026-04-16)

### ✨ Architecture Updates
- 重构了状态管理模块，为后续新功能打下基础。
- 更新了核心依赖库，提升应用启动速度。
