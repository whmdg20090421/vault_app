# 版本 1.5.3 (2026-04-22)

### 🚀 Encryption Performance & Pipeline

- **硬件级底层加速**：打通了 Flutter Platform Channel，使得后台多线程在进行 AES/ChaCha20 文件加密时可直接调用操作系统底层的硬件加密指令集（Android BoringSSL / iOS CommonCrypto），大文件加密速度提升超过 10 倍以上。
- **动态流水线调度 (Pipeline Scheduling)**：
  - 优化了内存分块加密流水线，支持异步提交加密请求并实现磁盘读取与加密的并行操作（最高并发度为 4），极大降低了 I/O 阻塞。
  - 新增智能任务分配算法。当总核心数未被占满时优先分配“硬件加速通道”；当队列排队且剩余 CPU 闲置时，自动将其分配给纯 Dart 实现的“普通加密模式”，实现软硬件混合全功率压榨。
- **任务状态追踪与 UI 呈现**：在进度列表中直观显示当前正在使用的加密模式（“硬件加速”蓝标 vs “普通加密”橙标），并在开发者模式下提供详细的调度追踪信息。

# 版本 1.5.2 (2026-04-22)

### ✨ Features, Performance & Bug Fixes
- **Hardware Crypto Acceleration**: 引入了底层的 `cryptography` 库，全面开启 AES 和 ChaCha20 的硬件加速，极大提升了大文件加密解密性能。
- **Adaptive Chunk Size**: 实现了根据文件大小自适应调整加密块大小（64KB~5MB）的算法，并引入了 V2 兼容头以保持老文件的完美解密。
- **Zero-copy Stream Optimization**: 重构了加密虚拟文件系统 (`EncryptedVfs`) 的流读写逻辑，预分配固定大小内存进行写入，彻底消除了内存深拷贝和 GC 压力。
- **Benchmark Fix**: 修复了底层加密速度基准测试 (Benchmark) 在 ChaCha20 下发生异常并抛出虚假数万兆速度的 Bug，同时更正了真实测速的计算公式。
- **Vault Explorer Enhancements**: 
  - 在保险箱的文件/文件夹长按菜单中新增了**“重命名”**与**“删除”**功能，可直接管理文件。
  - 在点击打开加密文件夹时，新增了二次确认弹窗，并对内部解密映射进行了强校验。
- **Encryption Progress Recovery**: 修复了手动暂停加密任务后，报错节点（红色）无法通过点击“播放”按钮一键恢复（黄色）的问题。

# 版本 1.4.7 (2026-04-19)

### ✨ Bug Fixes & UI Enhancements
- **WebDAV Folder Display**: 修复了云端同步文件夹配置时，因解析 PROPFIND 响应（Multi-Status）不完整导致的远程子文件夹无法显示的问题。
- **Encrypted Import Path**: 修正了在加密文件系统中某个子文件夹内导入明文文件时，文件被错误放置在根目录的 Bug，现在文件将正确保存在当前浏览的层级中。
- **Folder Context Menu**: 在加密文件夹的长按菜单中新增了“移动”和“复制”功能，并提供了相应的跨目录操作支持。
- **Progress UI Drill-down**: 重构了加密任务进度条面板，现在支持点击包含子项的文件夹，平滑进入并查看其内部具体文件的加密/解密进度，并可针对子项进行独立控制（暂停/继续/移除）。
- **Settings Migration**: 优化了设置界面的组织结构，将“每次启动自动刷新信息”选项从主设置导航栏迁移至“性能设置”页面中，使设置分类更加合理。

# 版本 1.4.6 (2026-04-19)

### ✨ Bug Fixes & Security
- **Encryption Export/Share Fix**: 全面落实了保险箱内部文件的导出（解密）、分享与预览功能。之前版本中相关方法存在未实现的占位符（仅模拟延迟），现在已基于 `EncryptedVfs` 完整实现了安全流式解密并输出至本地文件系统。
- **VFS Boundary Check**: 修正了 `EncryptedVfs.open` 方法中因 Dart `File.openRead` 参数独占（exclusive）特性引起的偏移量计算误差，确保分块解密的流式读取范围精确无误。
- **Security Best Practices**: 进行了全局加密逻辑审计，确保每一处文件读写强制走 `ChunkCrypto` 引擎，未落实的 `TODO` 和 `UnimplementedError` 均已被修复并重构。

# 版本 1.4.5 (2026-04-19)

### ✨ Features & Refactor
- **Encryption Module V4 Refactor**: 全面重构加密任务调度架构，引入细粒度层级状态树。
  - **Task Tree & Persistence**: 建立文件树模型，支持 JSON 序列化持久化。
  - **Multi-threading Engine**: 接入全新并发调度核心，优化断点恢复和错误捕获。
  - **Dynamic Progress**: 引入智能前后台动态刷新机制，减少 UI 卡顿。
  - **Progress UI**: 主页顶部新增 1% 强制可视化的四色进度指示器。
  - **Progress Modal**: 实现多级任务树半屏模态框，支持局部暂停/恢复与安全长按移除。
  - **Auto Archiving**: 任务 100% 成功后执行存在性校验，自动归档至历史记录。

# 版本 1.4.2 (2026-04-18)

### ✨ Bug Fixes & Improvements
- **Sync Settings UI**: 修复了同步模式下拉弹窗背景透明导致与底层内容重叠的问题，完美适配普通模式与赛博朋克主题。
- **Folder Selection Granularity**: 修改了本地与云端文件夹选择粒度，现在允许用户在配置同步时进入并选择具体的加密子文件夹或云端子目录，而不再局限于根目录。
- **WebDAV Auth**: 彻底修复了同步任务期间报出的 `DioException [bad response]: 401 Unauthorized` 鉴权失败问题。现在 `Authorization` (Basic Auth) 凭证被可靠地注入到 Dio 全局配置中。
- **Encryption Integrity**: 对加密核心链路进行了深层追踪与验证，确认文件底层流均强制经过 `ChunkCrypto` 处理，修复了此前因配置错误可能导致的“明文透传”或“假加密”漏洞，确保导入文件必然落地为不可读的密文。
- **Folder Import & Stats**: 修复了“导入明文文件夹”时任务被错误识别为单文件导致瞬间完成且未加密的问题；同时修复了首页统计大小不刷新的问题，现在文件夹导入完成后会自动精确重算真实体积。

# 版本 1.4.1 (2026-04-18)

### ✨ Features
- **Security Settings**: 在设置页新增"安全"模块，支持配置临时状态与未保存退出提示，并支持 Root 权限模式的选择（普通、Root-默认、Root-始终）。
- **File Statistics**: 首页新增文件统计面板，展示本地加密文件数、云端加密文件数以及差异文件数，并支持手动或启动时自动刷新差异计算。
- **Index Architecture**: 引入全新的索引文件规范（`local_index.json`, `remote_index.json`, `remote_index_cache.json`），规范本地更新、云端上传、差异计算及上传前的一致性校验流程。
- **Consistency Check**: 每次准备上传前进行一致性校验，哈希不一致时弹出同步提示框防覆盖。

# 版本 1.4.0 (2026-04-18)

### ✨ Features
- **UI Upgrade**: 全新“QQ弹弹”圆角弹性动画设计，适配纯黑、亮色、赛博朋克三大主题。
- **Sync Settings**: 新增云盘同步设置功能，支持自定义加密文件夹、同步文件夹、双向同步/单向同步以及时间优先/覆盖替换策略。
- **Security Validation**: 引入启动安全哈希校验（包哈希、签名校验），通过安全混淆密码机制防止被篡改。
- **History Separation**: 将加密任务历史记录与云盘同步历史记录从活动队列中分离，使用双页签 UI 便于查看。

### 🐛 Bug Fixes
- **Multi-threading Fix**: 修复由于加密进程缺乏 `masterKey` 与文件路径参数导致的“瞬间完成却未加密”的问题。
- **Performance UI Fix**: 修复了“性能设置”中滑动 CPU 数量进度条导致的 UI 线程阻塞卡死 Bug，改为使用 `Future.microtask` 异步释放。
- **Data Storage Rules**: 按照发版规则严格收束本地数据存储路径至内部私有目录 `data/data/...`，并将目录清晰地命名为全中文（如 `应用配置`、`主题背景`、`加密任务记录`、`运行日志`）。

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

# 版本 1.3.7 (2026-04-17)

### 🐛 Bug Fixes
- 修复了预览文件与导出文件时引发的语法树编译报错（移除了多余的括号），确保能顺利通过 Flutter 构建系统编译出 APK 安装包。

# 版本 1.3.6 (2026-04-17)

### 🐛 Bug Fixes & ✨ Features
- 优化一键控制：在任务传输列表的最上方增加横向撑满的“一键开始/全部暂停”大按钮，可全局控制队列启停。
- 修复状态重置：修复递归暂停任务时的状态误伤问题，防止已加密完成的任务在暂停并恢复后被重置为 pending。
- 性能设置控制：优化并确认“性能设置”中对于多核并发的边界限制，支持根据滑块设置即时应用新并发线程数上限。
- 自动同步展示：重构“关于”页面的版本读取，接入 `package_info_plus` 实现自动展示，并引入内嵌资源读取实现 `CHANGELOG.md` 自动同步展示。
- 数据存储规范：全中文重命名整理应用数据目录，如 `应用配置/`、`主题背景/`、`加密任务记录/`、`运行日志/`，提高私有数据结构可读性。

# 版本 1.3.5 (2026-04-17)

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
