# 任务列表 (Tasks)

- [ ] Task 1: 赛博朋克主题重构与纯黑主题新增。
  - [ ] SubTask 1.1: 搜索并修改当前赛博朋克主题，引入圆角（如 `BorderRadius.circular(12)`），并将背景调整为深色基调彩色。
  - [ ] SubTask 1.2: 新增“纯黑”主题（深黑背景，极简风格无发光边框），并接入到应用的主题切换逻辑中。

- [ ] Task 2: 修复 Android 侧滑/物理返回键的目录层级路由逻辑。
  - [ ] SubTask 2.1: 在 `vault_explorer_page.dart` 的顶层包裹 `PopScope`。
  - [ ] SubTask 2.2: 判断当前目录层级，若不在根目录，则在 `onPopInvoked` 中调用 `_cdUp()` 或类似返回上级的方法，并设置 `canPop` 为 `false`；若在根目录，则 `canPop` 为 `true`。

- [ ] Task 3: 重构主页“数据概览”UI 并接入真实统计逻辑。
  - [ ] SubTask 3.1: 在 `home_page.dart` 移除旧版饼图，使用 `Column` 与横跨屏幕的 `LinearProgressIndicator` 重构界面。
  - [ ] SubTask 3.2: 接入 `StatsService` 中的真实加密/未加密体积，并计算百分比，处理总量为 0 的边界情况以解决“0KB”的 Bug。

- [ ] Task 4: 文件列表体积单位自动换算。
  - [ ] SubTask 4.1: 实现 `formatBytes` 帮助函数，将字节数转换为带有 KB/MB/GB 单位的字符串。
  - [ ] SubTask 4.2: 在文件列表渲染的 UI 代码中应用该函数。

- [ ] Task 5: 修复 WebDAV 云盘真实连接报错。
  - [ ] SubTask 5.1: 在 WebDAV 客户端初始化的地方（如 `webdav_client_service.dart` 或 `webdav_client` 配置），添加全局的忽略 SSL 证书错误的回调。
  - [ ] SubTask 5.2: 检查并修改 `android/app/src/main/AndroidManifest.xml`，在 `<application>` 节点加入 `android:usesCleartextTraffic="true"`。