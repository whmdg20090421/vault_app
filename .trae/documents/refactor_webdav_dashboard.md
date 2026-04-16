# 优化云盘同步中枢 (WebDAV Dashboard) Spec

## 为什么 (Why)
当前主页（云盘页）的 WebDAV 卡片点击后仅调用网络请求查看根目录，属于缺乏业务深度的空壳 UI。
核心诉求是：彻底重构这一流程，引入一个专业的“同步管理仪表盘（Dashboard）”作为中枢，并将底层的 WebDAV 网络请求、状态统计、日志记录、以及真正的同步与删除逻辑全部详细落地，告别空壳 UI。

## 变更内容 (What Changes)
- **路由重构**：修改 `lib/cloud_drive/cloud_drive_page.dart`，拦截点击 WebDAV 卡片的路由，改为导航至全新的 `WebDAVDashboardPage`。
- **全局状态管理**：新增 `lib/cloud_drive/webdav_state_manager.dart`，实现基于 `ChangeNotifier` 的全局状态管理器 `WebDAVStateManager`（在 `main.dart` 注册）。它将负责在仪表盘各 Tab 以及文件列表之间共享数据（包含：最后同步时间、持续时间、同步状态、活动日志列表，以及各项统计计数）。
- **构建 `WebDAVDashboardPage`**：基于 `Scaffold` 和 `BottomNavigationBar`，包含三个 Tab：
  - **Tab 1: 概览 (Overview)**：展示“同步状态卡片”（最后同步时间、持续时间、当前状态）、“最近动态卡片”（上传/下载/删除计数）、“云存储信息卡片”。并增加本地保险箱选择/自动匹配的交互，供后续同步使用。
  - **Tab 2: 动态日志 (Activity)**：使用 `ListView.builder` 读取并展示全局状态管理器中的日志。日志根据操作类型（下载/上传/删除/完成/报错）显示不同的文本颜色，并且在执行网络动作时通过 `addLog()` 方法实时追加。
  - **Tab 3: 云端文件浏览 (File Browser)**：复用已有的云端目录读取展示逻辑，应用人类可读的文件大小换算，并接入真实的删除逻辑。
- **文件大小换算工具**：编写 `formatBytes` 函数，自动将 byte 转换为 KB, MB, GB, TB，并在文件浏览列表等处应用。
- **真实的 WebDAV 删除逻辑 (DELETE)**：
  - 确认底层网络服务中已有的 `DELETE` 接口。
  - 在文件浏览 Tab 列表项中添加长按或侧滑删除按钮。点击后调用底层真实的 `DELETE`。
  - 成功删除后：移除 UI 列表项，状态管理器“云端删除”统计 +1，并写入动态日志（如“已从云端删除：/path/to/file”）。
- **真实的同步比对引擎 (Sync Engine)**：
  - 在仪表盘的 `FloatingActionButton` 点击时触发 `startSync()`。
  - `startSync()` 内部详细实现：
    1. 调用 `PROPFIND` 获取当前云盘目录结构快照。
    2. 根据选择的本地保险箱，读取本地加密存储库的文件结构快照。
    3. 执行**差异比对 (Diffing)**：对比文件名、大小/修改时间，找出云端独有文件（标记为待下载），找出本地独有文件（标记为待上传）。
    4. 将比对过程的状态（如“获取云端列表成功”、“开始比对差异”）实时写入动态日志，并更新概览 Tab 的最后同步时间。
- **缓存与无效文件清理**：
  - 在开发前，主动清理项目中的无用缓存目录（如 `build/` 或临时文件）和冗余的空文件夹。
  - 整理现有的文件结构，并将在最终总结中输出具体被删除或整理的文件夹清单。
- **执行 TNG 版本发布规范**：
  - 阶段一：更新 `pubspec.yaml` 等配置文件的 Version Name 和自动 +1 Version Code。
  - 阶段二：同步更新应用内部的“关于”页面版本号与更新日志常量。
  - 阶段三：在分离的日志文件夹（如 `changelogs/`）中生成详细的新版本日志文档，并在 `README.md` 中添加简短摘要和超链接。
  - 阶段四：全局审查无误后，进行 Git Commit、打 Tag，并触发编译发布。执行每一步时会在终端或对话框中明确输出进度。

## 影响范围 (Impact)
- 影响模块：云盘管理模块、全局状态注册、UI 路由、同步核心逻辑。
- 影响代码：
  - `lib/main.dart`（注册全局 `WebDAVStateManager`）
  - `lib/cloud_drive/cloud_drive_page.dart`（修改导航目标）
  - `lib/cloud_drive/webdav_dashboard_page.dart`（新增文件）
  - `lib/cloud_drive/webdav_state_manager.dart`（新增文件）
  - `lib/utils/format_utils.dart`（新增工具类）

## ADDED Requirements
### Requirement: 专业的 WebDAV 仪表盘
系统必须提供一个具备全局状态管理的同步仪表盘，包括概览、动态日志、文件浏览三大板块。

#### Scenario: 执行真实删除
- **当** 用户在文件浏览 Tab 对某文件进行删除操作时
- **则** 系统调用真实的 `DELETE` 请求，从云端删除该文件；成功后更新 UI 列表，状态统计“云端删除”数 +1，并在动态日志中写入对应颜色的日志记录。

#### Scenario: 触发同步差异比对
- **当** 用户点击 `startSync()` 时
- **则** 系统并行拉取云端（PROPFIND）和本地目录快照，执行双向差异比对，将比对步骤与结果实时记入动态日志，同时更新状态面板的最后同步时间和状态。

## 假设与决策 (Assumptions & Decisions)
- **状态管理器生命周期**：根据确认，采用**全局级 (Global-Scoped)**。`WebDAVStateManager` 会在应用启动时注册，仪表盘页面关闭后状态依然保留。
- **本地保险箱映射**：在仪表盘中提供“自动匹配”与“手动选择”按钮。点击“自动匹配”时，系统将查找默认/匹配的保险箱；点击区域时弹出对话框让用户手动选择/解锁对应的本地保险箱，以满足读取本地快照的需求。
- **原生网络调用**：不引入新的第三方库，基于已有的 `HttpClient` 或 `Dio` 原生封装实现完整的 `DELETE` 和 `PROPFIND` 调用。

## 验证步骤 (Verification Steps)
1. 检查点击 WebDAV 卡片是否正确路由至带有 3 个 Tab 的新 Dashboard。
2. 验证“概览”Tab 的各项统计、时间是否正确绑定状态，且随着操作更新。
3. 验证“动态日志”Tab 是否能实时展示不同颜色的日志。
4. 验证“文件浏览”Tab 中文件大小已通过 `formatBytes` 换算。
5. 验证删除云端文件时，真实的 `DELETE` 请求发出，成功后 UI 移除、统计 +1、日志新增。
6. 验证点击同步按钮后，系统执行完整的 `PROPFIND` 和本地扫描，正确输出比对日志。