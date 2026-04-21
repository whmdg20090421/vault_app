# 任务执行计划 (Plan)

## 1. 摘要 (Summary)
本次任务主要解决您提出的三个问题：
1. **动画重叠问题**：修复点击新 UI 或返回时，因透明背景与默认路由过渡动画（特别是 iOS 风格滑动）冲突导致的“停顿并重叠”的视觉 Bug。
2. **重试按钮缺失**：为加密进度列表补充直观的单文件“重试”按钮以及全局的“一键重试”按钮，方便用户快速恢复报错的加密/解密任务。
3. **文件路径双斜杠报错 (PathNotFoundException)**：分析并确认文件路径中的 `//` 导致无法打开文件的问题，并说明该问题的修复情况。

## 2. 当前状态分析 (Current State Analysis)
* **问题 1**：在 `lib/theme/app_theme.dart` 中，由于为了实现一些特效，`scaffoldBackgroundColor` 和 `canvasColor` 被设置为透明 (`Colors.transparent`)。此时如果使用 `CupertinoPageTransitionsBuilder` 或 `OpenUpwardsPageTransitionsBuilder` 等带有位移的路由过渡，页面在滑动时无法遮挡下层页面，就会产生停顿和重叠。
* **问题 2**：在 `lib/encryption/widgets/encryption_progress_panel.dart` 中，错误任务的重试功能目前被隐藏在“长按菜单”中（“标记已修复并重试”），导致用户难以发现，且不支持一键重试所有报错。
* **问题 3**：`/storage/emulated/0//...` 路径包含多余的 `//`，在 Android 底层会抛出 OS Error 2（找不到文件）。此问题在 `LocalVfs` 拼接物理路径时未标准化导致。

## 3. 拟定修改与实现步骤 (Proposed Changes)

### 步骤 1：修复透明背景路由动画重叠 (Issue 1)
* **目标文件**：`lib/theme/app_theme.dart`
* **修改内容**：将 `defaultTheme` 和 `cyberpunk` 两个主题的 `PageTransitionsTheme` 统一修改为 `ZoomPageTransitionsBuilder(allowEnterRouteSnapshotting: false)` 或 `FadeUpwardsPageTransitionsBuilder()`。关闭 Snapshotting 并使用缩放/渐变过渡，可以完美解决透明 Scaffold 导致的滑动重叠与停顿问题。

### 步骤 2：添加单文件重试与一键重试按钮 (Issue 2)
* **目标文件**：`lib/encryption/widgets/encryption_progress_panel.dart`
* **修改内容**：
  1. **单文件重试**：在 `_EncryptionTaskCard` 组件内，如果检测到 `isError == true`，则在原本的错误图标旁（或卡片右侧）直接显示一个 **“重试”** (Refresh) 图标按钮，点击直接调用 `EncryptionTaskManager().markTaskAsFixed(task)`。
  2. **一键重试**：在 `EncryptionProgressPanel` 的顶部标题栏（与“关闭”按钮同级）添加一个 **“重试全部”** (TextButton.icon) 按钮。该按钮仅在当前列表中检测到含有 `NodeStatus.error` 的任务时显示，点击后会遍历并恢复所有失败的任务。

### 步骤 3：验证双斜杠路径报错的修复 (Issue 3)
* **目标文件**：`lib/vfs/local_vfs.dart`
* **处理方案**：在之前的会话中，我已经对 `LocalVfs.getRealPath` 函数进行了正则表达式替换修复（`realPath.replaceAll(RegExp(r'/+'), '/')`）。此逻辑**已经能够有效拦截并消除双斜杠 `//`**。
* **说明**：此问题在最新的代码中已经得到解决，当您使用最新编译的 APK（v1.5.0 及之后）时，将不再出现 `PathNotFoundException`。因此本次只需检查确认代码依然完好，无需进行大的逻辑变动。

## 4. 假设与决策 (Assumptions & Decisions)
* **决策**：路由动画改为缩放渐变过渡（Zoom / Fade）以适应透明背景，因为左右滑动的物理隐喻在透明背景下注定会穿帮。
* **决策**：一键重试功能只会遍历当前选项卡（进行中）的任务树，并将所有的 Error 节点重新排入队列。

## 5. 验证步骤 (Verification Steps)
1. 检查代码中的 `app_theme.dart` 是否已更新路由过渡构建器。
2. 运行 `dart analyze` 确保新加入的“重试”按钮和遍历逻辑没有语法错误。
3. 确认提交并通过 Github Action 编译新的 APK。