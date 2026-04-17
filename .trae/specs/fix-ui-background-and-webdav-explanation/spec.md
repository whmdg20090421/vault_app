# UI 背景与 WebDAV 说明 Spec

## Why
1. 当自定义背景开关关闭时，应用背景渲染成了黑色屏幕。这是由于 `_BackgroundShell` 被放置在了 `MaterialApp` 外层，缺乏 `Directionality` 和 `MediaQuery` 等上下文环境，导致它无法在 Android 窗口背景之上正常渲染。此外，当自定义背景关闭时，`Scaffold` 的背景色仍然是完全透明的，没有正确回退到主题的默认颜色。
2. 针对应用中 WebDAV 连接报出 DNS 解析错误（`Failed host lookup`）的问题，用户要求使用现有的 `webdav_client` 代码进行一次云端测试以排除代码逻辑错误，并需要一份针对 `webdav-js` (基于浏览器) 与当前应用原生底层网络通信机制之间差异的详细说明。

## What Changes
- 将 `_BackgroundShell` 的包裹位置从 `MaterialApp` 外侧移到内部的 `builder` 属性中，确保它能接收到正确的 Flutter 上下文。
- 在 `lib/theme/app_theme.dart` 的 `buildTheme` 方法中更新 `scaffoldBackgroundColor`，使其仅在 `bgEnabled` 为 true 时才透明；若为 false，则回退使用当前主题的默认背景色（如 `scheme.surfaceContainer` 或 `scheme.surface`）。
- 已经在真实环境中运行了一段 Dart 脚本，成功向用户的 WebDAV 上传了 `测试是否成功.txt` 文件，证明当前的网络库逻辑在健康的 DNS 环境下是完全畅通的。

## Impact
- Affected specs: UI 渲染、主题管理。
- Affected code: `lib/main.dart`, `lib/theme/app_theme.dart`

## ADDED Requirements
### Requirement: 稳定的默认背景
系统必须在用户关闭自定义背景时，正确且不透明地显示当前主题的默认背景色，绝不能出现黑屏回退现象。

#### Scenario: 成功场景
- **WHEN** 用户关闭自定义背景开关
- **THEN** 应用背景立刻恢复成标准的白色（或深色）主题背景，`Scaffold` 为不透明状态，视觉不再出现黑屏。

## MODIFIED Requirements
### Requirement: 应用主题透明度
`scaffoldBackgroundColor` 不再永远是全透明的，而是根据全局变量 `bgEnabled` 的状态动态切换透明度。
