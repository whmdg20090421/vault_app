# 修复与发布 v1.2.1 规范 (Spec)

## 为什么 (Why)
当前项目存在几个问题：GitHub Actions 工作流编译较慢且缺乏缓存机制；云盘挂载功能在域名解析失败时抛出底层报错，缺乏友好的错误处理与权限自获取；主页的“数据概览”UI在某些情况下会溢出卡片边缘；在加密页面导入文件时阻塞主线程，并且没有实时反馈状态。我们需要通过一系列细粒度的修复和优化，提升应用的稳定性和交互体验，最终实现 1.2.1 版本的全自动编译、自愈与发布。所有功能必须严格遵守 `.trae/rules.md` 中的规范，确保数据真实、逻辑完整。

## 变更内容 (What Changes)
- **优化 GitHub Actions 工作流**：在相关的 `.yml` 配置文件中添加 Flutter Pub 缓存和 Android Gradle 缓存，以加速构建过程。明确排除 `version.properties` 等可能引起版本号冲突的本地状态文件。添加 `workflow_dispatch` 手动触发选项以允许清除缓存/不使用缓存。
- **修复 WebDAV 网络异常**：捕获 `SocketException` 或 `DioException` 等网络请求错误（如 `webdav.123pan.cn` DNS 解析失败），并转换为友好的中文 UI 提示展示给用户。自动检测并配置 `AndroidManifest.xml` 的 `INTERNET` 权限。
- **修复主页 UI 布局溢出**：调整主页“数据概览”图表的布局容器约束，使用 `ClipRRect`、`LayoutBuilder` 或尺寸限制防止圆形组件溢出父级白色卡片边界。必须保证展示的是真实的统计数据。
- **优化加密任务交互逻辑**：选择加密文件/文件夹后，立即关闭选择弹窗和加载圈；将高耗时 IO 操作放入 `Isolate` 或 `compute` 中执行；同时将新任务同步到真实的“加密任务进度”状态中，使其能在进度面板展示为 0% 状态，并随着真实进度更新。
- **全局 UI 与接口调用自检**：对当前应用核心逻辑进行审查，解决潜在的内存泄漏、不当的 `setState` 调用以及无用重复渲染的问题，输出并应用相应的修复代码。
- **本地构建与发布闭环**：通过终端执行 Android 构建命令，自动检测、修改并修复任何编译错误（最多尝试 6 次），绝不抛出无法处理的权限或报错问题，最后将修复的代码提交 Git，发布 1.2.1 版本的正式版。

## 影响范围 (Impact)
- 影响的模块：GitHub Actions CI/CD，WebDAV 客户端请求，主页 UI 布局，加密页面异步处理逻辑，全局状态管理。
- 影响的代码：
  - `.github/workflows/` 下的构建和发布文件
  - `lib/cloud_drive/webdav_client_service.dart` 或相关网络请求代码
  - `android/app/src/main/AndroidManifest.xml`
  - `lib/home_page.dart` 及主页卡片布局
  - `lib/encryption/encryption_page.dart` 或导入处理逻辑
  - `lib/cloud_drive/cloud_drive_progress_manager.dart` 等核心状态管理文件
  - 构建发布的命令与脚本

## 新增需求 (ADDED Requirements)
### 需求：CI 依赖与构建缓存
系统必须在 GitHub Actions 编译时复用 Pub 和 Gradle 缓存，并支持手动清理缓存重新编译的功能。

#### 场景：成功案例
- **当** GitHub Actions 触发新的 Push 编译时
- **则** 自动还原上一轮的依赖缓存（如果 `pubspec.lock` 或 Gradle 没变），并加速构建，且绝对不会缓存 `version.properties` 导致版本冲突。

### 需求：后台任务与真实状态同步
系统必须在执行加密任务时释放 UI 线程，并在进度面板实时展示真实的进度数据。

#### 场景：成功案例
- **当** 用户选择一个大文件夹进行加密时
- **则** 选择窗口立刻消失，UI 继续保持响应，且加密进度面板中出现一条新的 0% 进度记录，并随真实 IO 进度更新。

## 修改的需求 (MODIFIED Requirements)
### 需求：优雅的网络错误处理与权限自理
现有的 WebDAV 请求如果遇到 DNS 失败等异常，系统必须捕获异常并抛出友好的中文 UI 错误提示。系统必须自行确保拥有网络权限，无需人工干预。
