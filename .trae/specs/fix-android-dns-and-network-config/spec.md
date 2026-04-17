# Fix Android DNS and Network Config Spec

## Why
在最近的重编译后，Flutter 项目在 Android 14/15 环境下遭遇了全局性的 DNS 解析故障，所有的网络请求均抛出 `DioException [connection error]: Failed host lookup`。尽管已经在 `AndroidManifest.xml` 中配置了必要的网络权限，但在现代 Android 系统中，依然需要通过更严谨的 `network_security_config` 以及兼容性更高的 SDK 配置来确保底层 TCP/UDP 访问能力和域名的正常解析。

## What Changes
- **Gradle SDK 配置**：推荐并调整 `android/app/build.gradle.kts`（或通过 Flutter 默认变量说明），确保 `compileSdk`、`targetSdk` 及 `minSdk` 符合 Android 14/15 (API 34/35) 的现代网络安全标准。
- **网络安全配置文件**：新增 `network_security_config.xml`，配置信任系统与用户证书，并合理放开明文流量（`cleartextTrafficPermitted="true"`），解决证书或域名被系统底层拦截的问题。
- **Manifest 挂载配置**：在 `AndroidManifest.xml` 的 `<application>` 标签中，追加挂载 `android:networkSecurityConfig="@xml/network_security_config"`。
- **Dart 终极诊断脚本**：提供一个仅依赖 `dart:io` 的网络与 DNS 诊断函数，用于在应用启动时快速区分是系统 DNS 瘫痪还是 App 缺乏底层网络权限，同时通过 `NetworkInterface.list()` 输出当前活跃的网络通道（如 WIFI、VPN、蜂窝数据），排查流量走向和网卡绑定问题。

## Impact
- Affected specs: 无
- Affected code:
  - `android/app/build.gradle.kts`
  - `android/app/src/main/res/xml/network_security_config.xml` (新增)
  - `android/app/src/main/AndroidManifest.xml`
  - 任意 Dart 测试文件（例如 `lib/utils/network_diagnostics.dart` 或直接提供代码片段供调用）

## ADDED Requirements
### Requirement: 增强型网络安全策略
系统 SHALL 在 Android 14/15 设备上正常发起 HTTP/HTTPS 请求，并且能够正常解析诸如 www.baidu.com 等公网域名。

#### Scenario: 成功解析域名并连接
- **WHEN** 应用启动或发起网络请求
- **THEN** 底层 `InternetAddress.lookup` 成功返回 IP，且网络连接不被系统安全策略阻断。

## MODIFIED Requirements
### Requirement: AndroidManifest 网络配置
原有的 `<application>` 仅配置了 `android:usesCleartextTraffic="true"`，现在需要增加自定义的网络安全配置挂载，以覆盖更严格的 Android 14+ 证书校验策略。
