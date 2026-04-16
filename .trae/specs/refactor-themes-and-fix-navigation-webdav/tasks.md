# 任务列表 (Tasks)

- [ ] Task 1: 赛博朋克主题重构与纯黑主题新增。
  - [ ] SubTask 1.1: 修改赛博朋克主题，引入圆角（如 `BorderRadius.circular(12)`），背景调整为深色渐变彩色。
  - [ ] SubTask 1.2: 新增“纯黑”主题（深黑背景，极简风格），确保不包含发光边框。

- [ ] Task 2: 修复 Android 侧滑/物理返回键的目录层级路由逻辑。
  - [ ] SubTask 2.1: 在 `vault_explorer_page.dart` 使用 `PopScope` 拦截返回事件。
  - [ ] SubTask 2.2: 实现逻辑：非根目录时返回上级并拦截退出，根目录时允许退出。

- [ ] Task 3: 全量数据真实化、缓存与主页 UI 重构。
  - [ ] SubTask 3.1: 审查并重构 `StatsService` 或相关统计模块，确保所有数据（已加密/未加密文件体积）均来自真实文件扫描或状态记录，并实现本地缓存。
  - [ ] SubTask 3.2: 重构 `home_page.dart` 数据概览 UI，使用横跨屏幕的 `LinearProgressIndicator` 展示真实统计数据。
  - [ ] SubTask 3.3: 统一所有 UI 模块的空状态展示，当真实数据为空时显示“暂无数据”，清理掉所有硬编码的模拟数据或占位符。

- [ ] Task 4: 文件列表体积单位自动换算。
  - [ ] SubTask 4.1: 实现并全局应用 `formatBytes` 函数。

- [ ] Task 5: 修复 WebDAV 云盘真实连接与网络配置。
  - [ ] SubTask 5.1: 在 WebDAV 请求底层添加忽略 SSL 证书校验的配置。
  - [ ] SubTask 5.2: 更新 `AndroidManifest.xml` 配置网络权限及明文传输支持。