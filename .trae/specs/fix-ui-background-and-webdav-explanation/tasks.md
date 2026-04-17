# 任务列表
- [x] Task 1: 修复 UI 背景渲染黑屏问题
  - [x] 修改 `lib/main.dart`，将 `_BackgroundShell` 从直接包裹 `MaterialApp` 调整为在 `MaterialApp.builder` 中使用，确保它被包裹在 Flutter 的根上下文中。
  - [x] 修改 `lib/theme/app_theme.dart` 中的 `buildTheme` 函数，当且仅当 `bgEnabled` 为 true 时，将 `scaffoldBackgroundColor` 设置为 `Colors.transparent`。若为 false，根据主题恢复到 `scheme.surfaceContainer`（对纯黑主题恢复到 `scheme.surface`）。
