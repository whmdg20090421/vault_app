# 加密文件选择器功能 Spec

## 为什么 (Why)
用户需要在“加密”导航栏中增加一个系统文件选择器，用于选择文件夹或文件。这是为未来要开发的加密功能提供需要被加密的文件来源。
应用应当仅在用户实际需要选择文件时，才动态申请文件访问权限，而不是在应用启动时就申请。同时需要注意权限申请的兼容性和完整性，完美适配各 Android 版本的存储权限规范。

## 做了哪些修改 (What Changes)
- 合并并清理了之前 WebDAV 相关任务（经检查已全部实现并发布 v1.0.1，故旧任务已删除）。
- 添加 `file_picker` 和 `permission_handler` 依赖。
- 更新 `AndroidManifest.xml` 以包含 `READ_EXTERNAL_STORAGE`、`WRITE_EXTERNAL_STORAGE` 和 `MANAGE_EXTERNAL_STORAGE` 权限。
- 将 `lib/main.dart` 中的占位符 `_TitlePage(title: '加密')` 替换为新的 `EncryptionPage`。
- 在 `EncryptionPage` 中实现美观的 UI，并使其适配现有的“默认”和“赛博朋克”两种主题。
- 实现具有版本兼容性的权限请求逻辑：Android 11 及以上申请 `MANAGE_EXTERNAL_STORAGE` (所有文件访问权限)；Android 10 及以下申请普通读写存储权限。权限请求只在用户尝试选择文件或文件夹时触发。
- 接入系统文件/文件夹选择逻辑，并在 UI 上展示已选择的路径。

## 影响范围 (Impact)
- 受影响的模块：无
- 受影响的代码：
  - `pubspec.yaml`
  - `android/app/src/main/AndroidManifest.xml`
  - `lib/main.dart`
  - `lib/encryption/encryption_page.dart` (新建文件)

## 新增需求 (ADDED Requirements)
### 需求：动态且兼容的权限请求
系统应当仅在用户点击选择文件或文件夹按钮时，才请求存储权限，禁止在应用启动时请求。必须保证申请权限的完整性和兼容性（针对 Android 11+ 请求 `Permission.manageExternalStorage`，Android 10 及以下请求 `Permission.storage`）。

#### 场景：成功情况
- **当 (WHEN)** 用户首次点击“选择文件”或“选择文件夹”按钮时
- **则 (THEN)** 系统根据当前 Android 版本弹出对应的存储权限/所有文件访问权限请求
- **当 (WHEN)** 权限被授予后
- **则 (THEN)** 系统调用底层文件选择器

### 需求：文件与文件夹选择
系统应当允许用户调用系统文件选择器来选择单个文件或文件夹，并在屏幕上显示所选路径，以便为后续的加密功能做好准备。

#### 场景：成功情况
- **当 (WHEN)** 用户选择了文件或文件夹后
- **则 (THEN)** UI 更新，美观地展示所选路径。
