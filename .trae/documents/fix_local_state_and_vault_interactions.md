# 修复本地状态断层与完善文件交互逻辑 Spec

## 为什么 (Why)
当前项目存在两个严重的本地业务逻辑断层问题：
1. 主页“数据概览”UI 没有实时同步本地加密保险箱的真实容量状态，导致已加密数据放入后依然显示“暂无数据”或 0KB。
2. 进入加密目录后，文件列表缺乏长按多选、删除、分享以及单击预览的交互逻辑，导致核心文件管理功能无法闭环。

## 变更内容 (What Changes)
- **修复主页状态同步 (StatsService & HomePage)**：
  - 将 `StatsService` 升级为 `ChangeNotifier`（全局状态管理器）。
  - 在 `HomePage` 的 `initState` 中触发 `StatsService().recalculate()`，并使用 `ListenableBuilder` 监听 `StatsService` 的变化，实现 UI 与本地数据的实时绑定。
  - 在涉及文件变动的地方（如加密任务完成、删除文件后），主动调用 `StatsService().recalculate()`。
- **完善加密目录交互 (VaultExplorerPage)**：
  - **多选模式 (Long Press)**：监听 `ListTile` 的 `onLongPress`，进入多选模式并显示 Checkbox。此时 `AppBar` 变为“已选择 X 项”，并提供“删除”与“分享”动作按钮。
  - **删除逻辑 (Delete)**：在多选模式下点击删除，弹出二次确认框。确认后，遍历选中的文件节点，调用 VFS 原生的 `_vfs.delete(node.path)` 删除文件，随后刷新列表并触发 `StatsService().recalculate()`。
  - **分享逻辑 (Share)**：由于文件处于加密状态，选中文件点击分享后，会在后台将加密文件流（`_vfs.open`）写入到 `path_provider` 提供的临时缓存目录（`getTemporaryDirectory()`），然后调用 `share_plus` 插件将解密后的临时文件分享出去。
  - **单击预览 (Single Tap)**：不在多选模式时，单击单个文件会将其临时解密到缓存目录，并调用 `open_filex` 插件打开文件（调用系统默认应用预览）。
- **修复编译错误**：
  - 修复 `lib/cloud_drive/webdav_browser_page.dart` 中由于缺少 `}` 导致的类定义未闭合编译报错（v1.2.3 的遗留问题）。
- **依赖更新**：
  - 在 `pubspec.yaml` 中新增 `share_plus` 和 `open_filex` 依赖。

## 影响范围 (Impact)
- 影响模块：主页数据概览、本地保险箱文件浏览、全局统计服务。
- 影响代码：
  - `pubspec.yaml`（新增依赖）
  - `lib/services/stats_service.dart`（状态管理升级）
  - `lib/home_page.dart`（UI 状态绑定）
  - `lib/encryption/vault_explorer_page.dart`（交互逻辑重构）
  - `lib/cloud_drive/webdav_browser_page.dart`（语法修复）

## ADDED Requirements
### Requirement: 文件分享与预览
系统必须支持加密文件的分享与外部预览，且必须在内存/临时目录中完成解密过渡，严禁直接分享加密密文。

#### Scenario: 单击预览加密图片
- **当** 用户在保险箱列表中单击一张加密图片时
- **则** 系统显示加载动画，将文件解密输出至临时目录，调用 `open_filex` 拉起系统相册查看，并在查看后（或退出应用时）依赖系统清理临时缓存。

## 修改的需求 (MODIFIED Requirements)
### 需求：主页数据概览实时同步
主页的概览统计不再仅依赖下拉刷新，必须在组件挂载时主动计算，并在全局任何地方增删文件后实时更新。

## 假设与决策 (Assumptions & Decisions)
- **解密性能与缓存清理**：分享与预览需要解密整个文件。对于超大文件可能较慢，因此在解密期间会展示全局 Loading 弹窗（`showDialog` -> `CircularProgressIndicator`）。临时文件存放在系统临时目录下，依赖系统自身的清理机制或在分享完成后主动删除。
- **删除逻辑的底层调用**：虽然用户提到“执行原生的 `file.deleteSync()`”，但在 Encrypted VFS 架构下，直接使用原生 `File` API 会破坏 VFS 映射层并导致解密失败。因此，必须通过 `_vfs.delete(node.path)` 进行底层调用，该方法在 `LocalVfs` 中最终会调用原生的文件删除逻辑，完全符合架构设计。

## 验证步骤 (Verification Steps)
1. 验证 `pubspec.yaml` 包含 `share_plus` 和 `open_filex`。
2. 验证修复 `webdav_browser_page.dart` 的语法错误，确保项目可以正常编译。
3. 验证主页加载时会自动计算并展示已加密的真实体积，无需手动下拉。
4. 验证在 `VaultExplorerPage` 中长按文件能进入多选模式，UI 变更为带有 Checkbox 和操作按钮的状态。
5. 验证多选删除文件后，列表自动刷新，主页的统计体积随之减少。
6. 验证单击文件能弹出 Loading，随后拉起第三方应用（预览成功）。
7. 验证多选文件分享能拉起系统分享面板。