# 修复背景闪烁与发布自动化 Spec

## Why
- 当前在底部导航栏（IndexedStack）内部切换页面时背景稳定，但在 Dialog/BottomSheet/路由跳转等交互触发时出现“背景短暂消失、闪回默认主题底色后恢复”的视觉闪烁，影响整体质感与稳定性。
- 发布流程中存在“版本号字段遗漏更新”的风险，需要在编译/发布阶段引入可验证的自动化校验与同步机制，确保仓库版本、构建产物版本与文档版本一致。
- 发布到 GitHub 后的更新日志呈现缺乏“摘要+详情分流”的自动化规范，导致 README 与详细变更难以同步且维护成本高。

## What Changes
- 背景渲染稳定化：
  - 将背景图片渲染从 `MaterialApp.builder` 的“每次路由/Overlay rebuild 可能触发的同步重建路径”中隔离出来，确保背景层在路由动画、Overlay 插入时不发生可见的重绘留白。
  - 为 `Image.file` 背景开启无缝渲染策略（如 `gaplessPlayback`）并引入预缓存（`precacheImage`）策略，避免解码/光栅化周期内的短暂留白。
  - 对 Dialog/BottomSheet/新页面等 Overlay/Route 组件进行透明度与背景色审计，避免出现默认 `canvasColor/scaffoldBackgroundColor` 在转场期间覆盖背景的瞬间。
- 发布流程增强（**BREAKING**：发布工作流会新增强制校验步骤，若未满足将直接失败）：
  - 编译期版本号自动正则替换（Automated Regex Version Injection）：在构建/发布前执行脚本，扫描项目内潜在的硬编码版本号字段并与目标版本同步，避免漏改。
  - 差异化 GitHub 更新日志发布（Differentiated Changelog Deployment）：自动生成并写入 README 摘要区，同时插入指向详细变更的链接（Release/CHANGELOG）以引导用户查看完整明细。

## Impact
- Affected specs: 全局背景渲染、路由/Overlay 体系、构建与发布流程、版本号管理、更新日志发布策略。
- Affected code:
  - 背景与主题：`lib/main.dart`、`lib/theme/background_settings.dart`、`lib/theme/app_theme.dart` 以及所有使用 Dialog/BottomSheet/路由跳转的页面
  - 发布与文档：`.github/workflows/build.yml`、`.github/workflows/release.yml`、`README.md`、`CHANGELOG.md`/`docs/changelogs/*`
  - 新增：发布辅助脚本（例如 `tool/release/*.dart` 或 `scripts/*`，以现有工程风格为准）

## ADDED Requirements
### Requirement: Background Stability
系统 SHALL 在以下交互过程中保持自定义背景稳定、无闪回默认底色：
- `Navigator.push/pop` 页面转场动画期间
- `showDialog` 弹窗出现/消失动画期间
- `showModalBottomSheet`/底部面板出现/消失动画期间

#### Scenario: Dialog
- **WHEN** 用户从任意 Tab 点击按钮打开对话框
- **THEN** 全程不出现默认主题底色“闪屏帧”，背景保持连续

#### Scenario: Route Push
- **WHEN** 用户从设置页进入子页面（`Navigator.push`）
- **THEN** 转场过程中背景保持连续且不闪回默认底色

### Requirement: Automated Regex Version Injection
系统 SHALL 在每次构建/发布前执行自动化脚本：
- 从 `pubspec.yaml` 解析目标版本号（如 `1.2.5+1`）
- 扫描并替换工程内所有“应与目标版本一致”的版本字段（含潜在硬编码）
- 若发现无法替换或存在残留旧版本号，构建 SHALL 失败并输出可定位的文件清单

### Requirement: Differentiated Changelog Deployment
系统 SHALL 在发布时自动生成并同步：
- README 摘要：仅展示本次版本核心变更（短文本）
- 详情链接：在 README 中插入明确链接指向 GitHub Release 或详细 changelog 文档

## MODIFIED Requirements
### Requirement: Background Rendering Path
背景渲染 SHALL 不依赖于 `MaterialApp.builder` 的频繁重建可见路径；背景层必须可被复用（稳定的 `ImageProvider` + 预缓存）并尽量避免在路由动画期间发生 image decode/repaint。

## REMOVED Requirements
### Requirement: Manual Version Sync
**Reason**: 人工手动同步版本号容易漏改，且难以在 CI 中可验证。
**Migration**: 统一由构建/发布脚本执行版本注入与校验，确保仓库、构建产物、文档一致。
