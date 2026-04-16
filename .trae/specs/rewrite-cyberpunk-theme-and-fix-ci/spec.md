# Rewrite Cyberpunk Theme and Fix CI Spec

## Why
当前内置的赛博朋克主题视觉效果不符合预期，需要进行彻底重写以符合极客感和高对比度规范。此外，现有的 Android `versionCode` 逻辑存在降级安装问题，需要修复以确保每次发布时版本号自增。同时，需要结合自动化提交流程，将新版本 (1.2.0) 自动修正编译错误并发布。

## What Changes
- **主题重构**：重新定义全局的深色极客风主题（背景色 `#0F1418` 或 `#12161A`，卡片背景色 `#1A2026` 且无圆角，主强调色 `#00E5FF`、次强调色 `#E040FB`、辅助强调色 `#FFEA00`，文本亮白 `#F0F8FF` 或灰青色 `#6B8294`）。
- **字体规范**：标题使用无衬线粗体且全大写，字间距拉开；涉及数据、容量、时间戳和系统状态的文字强制使用等宽字体 (Monospace)。
- **组件样式**：添加青色发光文字阴影，取消常规四面边框改用单边粗边框或准星折角线，按钮直角带发光，输入框底部边框激活，底部导航栏方块高亮且反转颜色，进度条极细无圆角。
- **版本控制修复**：修改 Android 构建配置 (`build.gradle` 等)，通过读取已有本地最新记录或自动化配置，确保 `versionCode` 能够准确读取并严格 +1，杜绝回退问题。
- **更新版本号**：将准备发布的 `versionName` 设置为 `1.2.0`。
- **全局除虫与工作流发布**：全局扫描修复潜在语法或逻辑 Bug，利用 Git 提交变更，触发工作流并自动读取编译报错进行修复循环，直至编译通过并发布正式版 `1.2.0`。

## Impact
- Affected specs: 主题视觉效果、Android 打包版本号控制、GitHub Actions 工作流与自动修复
- Affected code: 
  - `lib/theme/` 或对应赛博朋克主题文件、组件库
  - `android/app/build.gradle` 及其相关的版本号读取文件
  - `pubspec.yaml`
  - GitHub Actions 配置或其它依赖脚本（如遇编译失败时需修复的代码）

## ADDED Requirements
### Requirement: Cyberpunk Theme Override
The system SHALL provide a cyberpunk theme adhering to the precise color palette, typography (monospace for data), and specific UI elements (e.g., single-side cyan borders, cyan text shadows, no border-radius).

#### Scenario: Success case
- **WHEN** user views the app in the Cyberpunk theme
- **THEN** the app renders with `#0F1418` background, `#00E5FF` primary accents, sharp edges, and monospace fonts for numerical/system data.

### Requirement: Automatic Version Code Increment
The system SHALL strictly increment the Android `versionCode` on every new release to prevent downgrade installation errors.

#### Scenario: Success case
- **WHEN** a new release is built via CI
- **THEN** the `versionCode` is safely retrieved from a local record and guaranteed to be greater than the previously released version.

## MODIFIED Requirements
### Requirement: Release Automation and Auto-Healing
The system SHALL automatically commit, push, monitor CI workflow, intercept compilation errors by modifying code/dependencies iteratively, and ultimately publish release `1.2.0`.
