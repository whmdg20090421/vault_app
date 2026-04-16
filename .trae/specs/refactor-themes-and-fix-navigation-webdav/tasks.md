# 任务列表 (Tasks)

- [x] Task 1: 赛博朋克主题重构与纯黑主题新增。
  - [x] SubTask 1.1: 修改赛博朋克主题，引入圆角（如 `BorderRadius.circular(12)`），背景调整为深色渐变彩色。
  - [x] SubTask 1.2: 新增“纯黑”主题（深黑背景，极简风格），确保不包含发光边框。

- [x] Task 2: 全局自定义图片背景功能。
  - [x] SubTask 2.1: 在“关于”或设置导航栏中新增“背景自定义”菜单，点击打开一个包含：开关、选择图片按钮、UI 透明度滑动条、图片透明度滑动条的面板。
  - [x] SubTask 2.2: 使用文件选择器获取图片，并拷贝缓存至应用本地数据目录；将开关状态和透明度参数持久化存储（如 `SharedPreferences`）。
  - [x] SubTask 2.3: 修改应用的根 Widget 层级（如 `MaterialApp` 的 `builder` 或包裹所有页面的根视图），监听持久化的背景配置，若开关开启，则绘制所选的缓存图片作为背景，并对子界面的背景（如 `Scaffold` 和 `Card` 的颜色）应用设定的 UI 透明度。

- [x] Task 3: 修复 Android 侧滑/物理返回键的目录层级路由逻辑。
  - [x] SubTask 3.1: 在 `vault_explorer_page.dart` 使用 `PopScope` 拦截返回事件。
  - [x] SubTask 3.2: 实现逻辑：非根目录时返回上级并拦截退出，根目录时允许退出。

- [x] Task 4: 全量数据真实化、缓存与主页 UI 重构。
  - [x] SubTask 4.1: 审查并重构 `StatsService` 或相关统计模块，确保所有数据（已加密/未加密文件体积）均来自真实文件扫描或状态记录，并实现本地缓存。
  - [x] SubTask 4.2: 重构 `home_page.dart` 数据概览 UI，使用横跨屏幕的 `LinearProgressIndicator` 展示真实统计数据。
  - [x] SubTask 4.3: 统一所有 UI 模块的空状态展示，当真实数据为空时显示“暂无数据”，清理掉所有硬编码的模拟数据或占位符。

- [x] Task 5: 文件列表体积单位自动换算。
  - [x] SubTask 5.1: 实现并全局应用 `formatBytes` 函数。

- [x] Task 6: 修复 WebDAV 云盘真实连接与网络配置，参考 JS 库实现底层核心通信逻辑。
  - [x] SubTask 6.1: 在 WebDAV 请求底层添加忽略 SSL 证书校验的配置。
  - [x] SubTask 6.2: 更新 `AndroidManifest.xml` 配置网络权限及明文传输支持。
  - [x] SubTask 6.3: 参考 `dom111/webdav-js` 的核心逻辑（如 `PROPFIND`, `DELETE`, `MKCOL`），使用 Dart 网络库构造 XML 请求体和解析响应。
  - [x] SubTask 6.4: 实现真实的云盘浏览和文件模型映射，支持点击进入子目录。
  - [x] SubTask 6.5: 实现删除云盘文件/文件夹功能，并更新 UI 状态。
  - [x] SubTask 6.6: 实现云端文件与本地已加密文件的比对机制，在 UI 上标记“已同步/未同步”状态。

- [ ] Task 7: 全局自检。
  - [ ] SubTask 7.1: 在前面所有任务完成后，全局检查所有代码、业务逻辑与 UI 溢出情况，修复潜在问题。

- [ ] Task 8: 自动化提交、编译、纠错与发布 v1.2.2。
  - [ ] SubTask 8.1: 使用 Git 提交代码至仓库，触发 GitHub Actions 编译。
  - [ ] SubTask 8.2: 监控编译报错并自动修改代码，循环重试直至成功。
  - [ ] SubTask 8.3: 成功后发布为 `1.2.2` 正式版本（Release 描述仅包含当前版本的更新日志）。