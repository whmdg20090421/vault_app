# Refactor WebDAV Sync and Fix Background Flicker Spec

## Why
1. 当在底部导航栏局部切换页面时背景稳定，但触发页面重绘或新路由时，自定义背景图片会消失闪烁。关闭背景图时因为 Scaffold 透明导致黑屏。
2. 原有的 WebDAV 实现不够健壮，缺乏标准的 XML 解析与增量同步机制。需要参考 webdav-js 的思路，使用 `dio` 和 `xml` 包重构出一个基于 Clean Architecture 的高性能 Flutter WebDAV 核心库。

## What Changes
- 修改全局背景渲染组件，在 `MaterialApp.builder` 级别使用 `Stack`。底层铺设 `Theme.of(context).scaffoldBackgroundColor` 作为兜底，上层渲染图片并开启 `gaplessPlayback: true`。
- 确保相关页面的 `Scaffold` 以及弹窗等组件的背景色设为 `Colors.transparent`。
- 删除旧的 WebDAV 相关代码。
- 新增 `WebDavClient`：基于 `dio`，支持自定义 HTTP 方法和全局异常捕获。
- 新增 `WebDavParser`：基于 `xml` 包解析 WebDAV multistatus 响应，提取 href、getcontentlength、getetag 和 resourcetype。
- 新增 `WebDavService`：提供 list、upload、download、move 等核心业务接口。
- 新增 `SyncEngine`：提供基于 ETag 的增量同步逻辑。

## Impact
- Affected specs: UI 渲染、背景管理、WebDAV 同步模块
- Affected code: `lib/main.dart`、`lib/theme/app_theme.dart` 以及所有的 WebDAV 相关网络服务代码。

## ADDED Requirements
### Requirement: 稳定的背景渲染
系统必须在切换路由或重绘时保持背景图片稳定不闪烁，并在关闭背景图片时显示正确的主题底色。

#### Scenario: Success case
- **WHEN** 用户点击组件触发路由跳转或局部重绘
- **THEN** 背景图片通过 `gaplessPlayback` 无缝显示，没有任何闪烁或黑屏。

### Requirement: 高性能 WebDAV 同步
系统必须提供一个解耦的、易于维护的 WebDAV 客户端库，支持标准的 XML 响应解析和基于 ETag 的增量同步。

#### Scenario: Success case
- **WHEN** 用户触发云盘同步
- **THEN** 系统通过对比远端 ETag 与本地记录，仅下载有变化的文件，提高同步效率。

## MODIFIED Requirements
### Requirement: 移除旧版 WebDAV 代码
**Reason**: 旧版实现耦合度高且不支持高级同步特性。
**Migration**: 删除无用代码，全面切换至新版 `WebDavService`。
