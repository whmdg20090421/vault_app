# Flutter APK + GitHub Actions 方案（天眼·艨艟战舰）

## Summary
在当前仓库（仅存在空的 [build.yml](file:///workspace/.github/workflows/build.yml)）中新增一个最小可运行的 Flutter 应用骨架，并提供 GitHub Actions 工作流：当 push 到 `main` 分支时自动使用 **Flutter 3.x 最新稳定版** 编译 **arm64-v8a release APK**，并使用仓库 Secrets（`KEY_STORE_BASE64 / KEY_ALIAS / KEY_PASSWORD / STORE_PASSWORD`）完成 Android release 签名；构建产物以 Actions Artifact 形式上传。

## Current State Analysis
- 仓库当前仅包含：
  - [build.yml](file:///workspace/.github/workflows/build.yml)（空文件）
- 未发现 Flutter 工程文件（未找到 `pubspec.yaml`、`android/` 等目录）。

## Proposed Changes

### 1) 新建 Flutter 应用骨架
**目标**
- App 显示名：`天眼·艨艟战舰`
- Android 包名（applicationId）：`com.tianyanjcz.vault`
- 主界面：BottomNavigationBar，4 个 Tab：`主页 / 云盘 / 加密 / 设置`；每页仅展示标题文字。

**将新增/生成的核心文件（按 flutter create 结构）**
- `pubspec.yaml`
  - `name: vault`（Dart package 名称，与 Android applicationId 无强制绑定，但建议保持一致、简短）
  - Flutter SDK 约束：`>=3.0.0 <4.0.0`（兼容 Flutter 3.x 稳定版）
- `lib/main.dart`
  - `MaterialApp` + `Scaffold`
  - `BottomNavigationBar(type: fixed)`，4 个 item
  - `IndexedStack`（或等价方案）保留 Tab 状态
  - 每个页面使用 `Center(Text('主页'))` 等
- `android/`（Flutter Android 工程）
  - `android/app/src/main/AndroidManifest.xml`
    - `android:label="@string/app_name"`（保持引用）
  - `android/app/src/main/res/values/strings.xml`
    - `app_name` 设置为 `天眼·艨艟战舰`
  - `android/app/build.gradle`（或 `build.gradle.kts`，以实际生成版本为准）
    - 加入 release signingConfig：从 `key.properties` 读取签名参数
  - `android/key.properties`（不提交；CI 运行时生成）
    - 内容形如：
      - `storePassword=...`
      - `keyPassword=...`
      - `keyAlias=...`
      - `storeFile=../keystore.jks`（或 `keystore.jks`，按 decode 文件位置确定）
  - `android/keystore.jks`（不提交；CI 运行时由 `KEY_STORE_BASE64` 解码生成）

**实现细节**
- 创建工程的方式：
  - 优先用 `flutter create --org com.tianyanjcz --project-name vault .` 在仓库根目录初始化（确保生成完整标准结构与 Gradle 配置），再按需要修改显示名、UI 与签名读取逻辑。
- Android 包名：
  - 通过 `--org com.tianyanjcz` + `--project-name vault` 生成 `com.tianyanjcz.vault`
  - 若生成结果与期望不一致，再在 `android/app/build.gradle*` 的 `applicationId` 处修正为 `com.tianyanjcz.vault`

### 2) Android Release 签名（基于 Secrets）
**目标**
- 仅在 CI 或本地提供 `key.properties + keystore.jks` 时启用 release 签名；未提供时不影响 debug 构建。

**将修改**
- `android/app/build.gradle*`
  - 在 `android { signingConfigs { release { ... } } buildTypes { release { signingConfig signingConfigs.release } } }` 中加入签名配置
  - 使用 `Properties` 从 `android/key.properties` 读取：`storePassword / keyPassword / keyAlias / storeFile`
  - 对文件不存在的情况做保护：如果 `key.properties` 不存在，则不配置 release signing（避免本地开发报错）

### 3) GitHub Actions：push main 自动构建 arm64-v8a release APK 并上传 Artifact
**将替换/重写**
- `.github/workflows/build.yml`

**工作流关键点**
- 触发：`on: push: branches: [main]`
- Flutter 安装：使用 `subosito/flutter-action@v2`
  - `channel: stable`
  - `flutter-version: 3.x`（自动获取最新 3.x 稳定版）
  - 启用缓存（action 自带 cache 选项，或搭配 actions/cache）
- Java：Android 构建需要 JDK（建议 17，跟随当前 Android/Gradle 默认需求）
- 签名注入（来自 Secrets）：
  1. `echo "$KEY_STORE_BASE64" | base64 -d > android/keystore.jks`
  2. 生成 `android/key.properties`（由 Secrets 写入）
- 构建命令：
  - `flutter pub get`
  - `flutter build apk --release --split-per-abi`
  - 产物位置：`build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`
- 上传 Artifact：
  - `actions/upload-artifact@v4`
  - name 示例：`apk-arm64-v8a-release`
  - path 指向上述 APK 文件

**安全约束**
- 不在日志打印 Secrets 内容
- `key.properties` 与 `keystore.jks` 仅在 runner 的工作目录中生成，不写入仓库

## Assumptions & Decisions
- 仅支持 Android APK（不包含 iOS / AAB）
- 产物仅上传 Actions Artifact（用户已确认）
- ABI 方案使用 `--split-per-abi`，并仅上传 `app-arm64-v8a-release.apk`（用户已确认）
- Flutter 工程使用标准 `flutter create` 生成结构，减少手工维护的 Gradle 差异风险

## Verification Steps
### 本地（可选）
- `flutter --version` 确认为 3.x
- `flutter pub get`
- 不配置签名时：`flutter build apk --debug` 可通过
- 提供 `android/key.properties + android/keystore.jks` 后：`flutter build apk --release --split-per-abi` 生成 `app-arm64-v8a-release.apk`

### CI（必做）
- push 到 `main` 后，Actions workflow 成功
- 构建产物中包含 `apk-arm64-v8a-release` artifact，且内含 `app-arm64-v8a-release.apk`

