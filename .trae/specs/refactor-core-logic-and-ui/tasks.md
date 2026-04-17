# Tasks

- [x] Task 1: 准备工作与依赖引入
  - [x] SubTask 1.1: 在 `pubspec.yaml` 中添加 `dio`, `path_provider`, `image_picker`, `xml` 等必要依赖。

- [x] Task 2: WebDAV 同步引擎的真正落地与入口重构
  - [x] SubTask 2.1: 移除外层云盘主页的“新建同步任务”按钮，将入口转移至 `WebDAVDashboardPage`。
  - [x] SubTask 2.2: 参考 `dom111/webdav-js`，使用 Dio 实现 `PROPFIND` 请求，解析返回的 XML 以提取 `getlastmodified`、`getcontentlength` 等属性。
  - [x] SubTask 2.3: 实现差异比对引擎，对比本地与云端文件状态，执行真实的 HTTP PUT（上传）、GET（下载）、DELETE（删除）和 MKCOL（建目录）操作。
  - [x] SubTask 2.4: 在仪表盘日志面板中实时记录并显示这些双向传输的状态。

- [x] Task 3: 修复 WebDAV 连通性顽疾与日志持久化
  - [x] SubTask 3.1: 深入排查并重构网络请求工具类，修复 Host 和 Headers（如 Depth, Destination）的配置，解决 `Failed host lookup` 问题。
  - [x] SubTask 3.2: 使用 `path_provider` 拦截全局网络异常，将详细错误堆栈写入 Android 外部私有目录（`getExternalStorageDirectory()`）的特定日志文件中。

- [x] Task 4: 重构加密引擎 (Isolate) 与递归式目录进度 UI
  - [x] SubTask 4.1: 创建基于 `Isolate` 或 `compute` 的加密/解密文件流服务，消除高耗时任务导致的 UI 假死。
  - [x] SubTask 4.2: 重构加密任务 UI，实现可点击进入子文件夹的层级树视图（类似文件管理器）。
  - [x] SubTask 4.3: 实现进度冒泡统计规则，实时计算并显示节点及其所有子节点的总大小、已加密大小和总百分比。

- [x] Task 5: 主页“数据概览”UI 科技感重塑
  - [x] SubTask 5.1: 使用 `LinearGradient`, `BoxShadow` 和 `TweenAnimationBuilder` 重绘主页进度条，实现发光与生长动画。
  - [x] SubTask 5.2: 更新数据文本拼接逻辑，强制追加具体百分比，格式严格遵循：`🟩 已加密: 32.16 MB (100%)`。

- [x] Task 6: 构建“主题与背景设置”系统
  - [x] SubTask 6.1: 新建“主题与背景设置”二级页面，迁移默认主题选项。
  - [x] SubTask 6.2: 集成 `image_picker`，实现自定义背景图片选择，并使用 `File.copy()` 将其复制到内部私有目录。
  - [x] SubTask 6.3: 添加并绑定两个 Slider：一个控制全局 UI 组件透明度，一个控制背景图遮罩透明度。

- [x] Task 7: 更新 AI 行为规范与版本日志
  - [x] SubTask 7.1: 修改 `.trae/rules.md`，添加“发版强制规范”（追加模式更新 Changelog）。
  - [x] SubTask 7.2: 检查并补全 README 或日志文档中遗失的 1.2.0、1.2.1、1.2.2 版本的占位记录。

# Task Dependencies
- Task 2 和 Task 3 依赖于 Task 1
- Task 4 依赖于 Task 1
- Task 6 依赖于 Task 1
