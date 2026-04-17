# 核心业务逻辑落地与 UI 深度重构 Spec

## Why
当前应用存在大量底层业务逻辑缺失、WebDAV 网络连通性异常、加密耗时任务阻塞主线程（假死）以及部分 UI 缺乏科技感等问题。为了提升应用的稳定性、性能和用户体验，需要进行一次深度的核心逻辑重构与 UI 优化。特别是参考 `dom111/webdav-js` 的实现，我们需要抛弃只做表面功夫的 UI，转而利用 `PROPFIND`、XML 解析及标准的 HTTP 方法（PUT、GET、MKCOL、DELETE）实现真实的双向差异同步引擎。

## What Changes
- **重构 WebDAV 同步引擎与入口**：移除主页的同步任务新建按钮，强制绑定至 `WebDAVDashboardPage`。参考 `dom111/webdav-js` 的协议封装逻辑，使用原生网络库（Dio）发送 `PROPFIND` 获取远端文件树，通过解析 XML (如 `getlastmodified`, `getcontentlength`) 与本地文件系统比对差异，进而利用 HTTP PUT、GET、DELETE 和 MKCOL 完成真实的双向同步。
- **修复网络连接与添加日志**：深入排查 `webdav.123pan.cn` 的 `Failed host lookup` 问题，拦截全局异常并持久化保存错误堆栈至 Android 外部私有目录（`getExternalStorageDirectory()`）。
- **重构加密引擎与递归视图**：将加密/解密文件流迁移至独立的 `Isolate` (或 `compute`)，防止主线程阻塞。实现类似文件管理器的递归式目录视图，并支持进度冒泡统计规则。
- **重塑主页数据概览 UI**：为进度条添加科技感（渐变色、发光阴影、生长动画），强制追加精细化的百分比和数据大小文本（如：`🟩 已加密: 32.16 MB (100%)`）。
- **构建主题与背景设置系统**：抽离“主题与背景设置”二级页面，实现相册选图自定义背景，并将图片使用 `File.copy()` 复制到内部私有目录。提供双轨透明度控制滑块（UI 组件透明度与背景遮罩透明度）。
- **更新 AI 行为规范与日志**：在 `.trae/rules.md` 中增加发版追加规则，并主动补齐缺失的 1.2.0、1.2.1、1.2.2 版本号记录。
- **BREAKING**: 原有主页云盘模块的“新建同步任务”交互被移除；原有加密页面的扁平化进度列表将被全新的递归树形结构替代。

## Impact
- Affected specs: 云盘同步模块、本地加密模块、主题设置模块。
- Affected code: 
  - `pubspec.yaml` (新增 `dio`, `path_provider`, `image_picker`, `xml` 等依赖)
  - `lib/cloud_drive/webdav_dashboard_page.dart`
  - `lib/cloud_drive/webdav_client.dart` 或底层网络类
  - `lib/encryption/encryption_isolate.dart` (新增)
  - `lib/home/home_page.dart`
  - `lib/settings/theme_settings_page.dart` (新增)
  - `.trae/rules.md` 和 `CHANGELOG.md`

## ADDED Requirements
### Requirement: 标准的 WebDAV 双向同步引擎
系统必须通过 `PROPFIND` 结合 XML 解析获取目录状态，计算与本地的差异，然后通过 PUT/GET/DELETE 等标准 HTTP 请求进行双向同步，并实时反馈日志。

#### Scenario: 触发全量同步
- **WHEN** 用户在仪表盘点击“开始同步”
- **THEN** 系统发送 `PROPFIND` 获取云端列表，解析 XML 对比本地文件。对缺失文件调用 GET 下载或 PUT 上传，多余文件调用 DELETE，并在日志板块显示实时传输状态。

### Requirement: 独立线程的加密任务与递归统计
系统必须在后台线程处理加密流，并在前台递归计算文件夹整体进度。

#### Scenario: 加密包含大量文件的深层文件夹
- **WHEN** 用户选择一个深层文件夹进行加密
- **THEN** UI 保持流畅，文件夹节点能够点击展开子目录，并且父级节点的进度条能根据子节点进度实时冒泡更新。

## MODIFIED Requirements
### Requirement: 科技感数据概览
修改主页“数据概览”进度条，必须使用渐变色、阴影，并在加载时应用 `TweenAnimationBuilder` 生长动画，同时文本格式严格要求。

## REMOVED Requirements
### Requirement: 主页快捷新建同步任务
**Reason**: 统一入口以避免状态冲突和逻辑分散。
**Migration**: 引导用户进入 `WebDAVDashboardPage` 操作。
