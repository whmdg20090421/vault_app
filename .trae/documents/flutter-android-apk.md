# Flutter Android APK 计划（天眼·艨艟战舰）

## Summary
- 在仓库根目录创建一个仅 Android 的 Flutter 应用（Flutter 3.x 最新稳定版），应用显示名为“天眼·艨艟战舰”，包名为 `com.tianyanmczj.vault`。
- 主界面使用 Material 3 风格，包含 4 个可切换 Tab（主页/云盘/加密/设置）的底部导航栏，仅展示标题文本。
- 配置 GitHub Actions：push 到 main 分支时自动构建 `arm64-v8a` 的 release APK，并使用仓库 Secrets 进行签名。

## Current State Analysis
- 仓库当前仅存在空的工作流文件：[build.yml](file:///workspace/.github/workflows/build.yml)（0 行）。
- 未检测到 Flutter 工程（无 `pubspec.yaml`、无 `android/` 目录），需要从零初始化项目结构。

## Proposed Changes

### 1) 初始化 Flutter 工程（仅 Android）
**目标**：生成标准 Flutter App 结构，但只启用 Android 平台，并让默认包名落在 `com.tianyanmczj.vault`。

**将执行的命令（在仓库根目录）**
```bash
flutter create \
  --platforms=android \
  --org com.tianyanmczj \
  --project-name vault \
  --android-language kotlin \
  .
```

**说明**
- `--platforms=android` 确保不生成 iOS/Web/桌面端目录。
- 通过 `--org com.tianyanmczj` + `--project-name vault` 让 Android 侧包名/namespace 目标为 `com.tianyanmczj.vault`（后续仍会在 Android 配置文件中核对并修正）。

### 2) 应用显示名与包名落地
**目标**：Android 桌面显示名为“天眼·艨艟战舰”；包名严格为 `com.tianyanmczj.vault`。

**修改文件（初始化后会出现）**
- `android/app/src/main/AndroidManifest.xml`
  - 设置 `android:label` 指向字符串资源（或直接写死为“天眼·艨艟战舰”，但推荐使用资源）。
- `android/app/src/main/res/values/strings.xml`
  - `app_name` 设置为 `天眼·艨艟战舰`。
- `android/app/build.gradle`（或 `android/app/build.gradle.kts`，以实际生成结果为准）
  - `namespace` 与 `applicationId` 统一为 `com.tianyanmczj.vault`。
- `android/app/src/main/kotlin/com/tianyanmczj/vault/MainActivity.kt`
  - `package com.tianyanmczj.vault` 与目录结构保持一致（必要时移动文件路径）。

### 3) 主界面：Material 3 + Bottom Navigation（4 Tab）
**目标**：页面美观、Material 3 风格明显，4 个 Tab 可正常点击切换，每页只显示对应标题文字。

**修改文件**
- `lib/main.dart`

**实现要点（决策已锁定）**
- 使用 `MaterialApp` + `ThemeData(useMaterial3: true, colorSchemeSeed: …)` 统一配色。
- 使用 `Scaffold` + Material 3 的 `NavigationBar`（而不是旧的 `BottomNavigationBar`）实现底部导航。
- 4 个 `NavigationDestination`：
  - 主页：`Icons.home_rounded`
  - 云盘：`Icons.cloud_rounded`
  - 加密：`Icons.lock_rounded`
  - 设置：`Icons.settings_rounded`
- 内容区使用 `IndexedStack` 保持各 Tab 状态（即便当前只显示标题，也更符合真实 App 结构）。
- 每个页面仅 `Center(Text('标题'))`，字体使用 `Theme.of(context).textTheme.headlineMedium` 并配合 `FontWeight.w600`，使视觉更精致。

### 4) Android Release 签名（使用 GitHub Secrets）
**目标**：本地不提交任何敏感信息；CI 构建时通过 Secrets 写入 keystore 与 key.properties 完成签名。

**使用的 Secrets（用户已指定）**
- `KEY_STORE_BASE64`：keystore 文件 base64
- `KEY_ALIAS`
- `KEY_PASSWORD`
- `STORE_PASSWORD`

**仓库侧改动（初始化后会出现）**
- `android/app/build.gradle`（或 `build.gradle.kts`）
  - 增加 `signingConfigs { release { ... } }`，从 `android/key.properties` 读取参数。
  - `buildTypes { release { signingConfig signingConfigs.release } }`
  - 约束：当 `android/key.properties` 不存在时，release 构建应仍可在本地以未签名（或使用默认 debug 签名）方式进行（避免影响本地开发）。
- `.gitignore`
  - 忽略 `android/key.properties` 与 `android/app/keystore.jks`（或实际保存路径）。

**CI 中生成文件（不提交到仓库）**
- `android/app/keystore.jks`：由 `KEY_STORE_BASE64` 解码写入
- `android/key.properties`：写入别名与密码

### 5) GitHub Actions：push main 自动构建 arm64-v8a release APK
**目标**：在 `main` 分支 push 时触发，执行 `flutter build apk` 输出仅 `arm64-v8a` 架构的 release APK，并上传为 workflow artifact。

**修改文件**
- [build.yml](file:///workspace/.github/workflows/build.yml)（将替换为空文件内容为可用工作流）

**工作流设计（决策已锁定）**
- 触发器：`on: push: branches: [main]`
- Runner：`ubuntu-latest`
- 环境：
  - `actions/setup-java@v4`（Temurin 17，匹配当前 Flutter/AGP 常用组合）
  - `subosito/flutter-action@v2`（`channel: stable`，`flutter-version: '3.x'`）
- 构建步骤：
  1. checkout
  2. 写入 keystore 与 key.properties（从 Secrets）
  3. `flutter pub get`
  4. `flutter build apk --release --target-platform android-arm64`
  5. 上传 `build/app/outputs/flutter-apk/app-release.apk` 为 artifact（命名包含 `arm64` 与 commit SHA）

**Secrets 配置建议（使用 gh-cli）**
在本地已 `gh auth login` 的情况下：
```bash
printf '%s' "$KEY_STORE_BASE64" | gh secret set KEY_STORE_BASE64
printf '%s' "$KEY_ALIAS" | gh secret set KEY_ALIAS
printf '%s' "$KEY_PASSWORD" | gh secret set KEY_PASSWORD
printf '%s' "$STORE_PASSWORD" | gh secret set STORE_PASSWORD
```

## Assumptions & Decisions
- 仓库允许在根目录直接生成 Flutter 工程（即最终结构为 `pubspec.yaml`、`android/`、`lib/` 等位于仓库根目录）。
- Android 使用 Kotlin MainActivity（`--android-language kotlin`）。
- 仅要求构建并产出 APK artifact；不自动创建 GitHub Release（若需要，可在后续追加 tag 触发发布流程）。
- `KEY_STORE_BASE64` 对应的 keystore 为 JKS/PKCS12 均可，只要 Android Gradle 能读取；CI 侧统一保存为 `keystore.jks` 并通过 `storeFile` 引用。

## Verification Steps
### 本地（开发机）
```bash
flutter --version
flutter pub get
flutter analyze
flutter build apk --release --target-platform android-arm64
ls -lah build/app/outputs/flutter-apk/
```

### CI（GitHub Actions）
- push 到 `main` 后，在 Actions 页面确认 workflow run 成功。
- 下载 artifact，确认 APK 文件存在且可安装到 arm64 设备/模拟器。

