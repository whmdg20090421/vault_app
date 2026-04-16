# 加密文件选择器功能 Spec

## 为什么 (Why)
用户需要在“加密”导航栏中增加一个系统文件选择器，用于选择文件夹或文件。这是为未来要开发的加密功能提供需要被加密的文件来源。应用应当仅在用户实际需要选择文件时，才动态申请文件访问权限（包括所有文件访问权限），而不是在应用启动时就申请。

## 做了哪些修改 (What Changes)
- 添加 `file_picker` 和 `permission_handler` 依赖。
- 更新 `AndroidManifest.xml` 以包含 `READ_EXTERNAL_STORAGE`、`WRITE_EXTERNAL_STORAGE` 和 `MANAGE_EXTERNAL_STORAGE` 权限。
- 将 `lib/main.dart` 中的占位符 `_TitlePage(title: '加密')` 替换为新的 `EncryptionPage`。
- 在 `EncryptionPage` 中实现美观的 UI，并使其适配现有的“默认”和“赛博朋克”两种主题。
- 实现权限请求逻辑，只有当用户尝试选择文件或文件夹时才触发权限请求。
- 实现系统文件/文件夹选择逻辑，并在 UI 上展示已选择的路径。

## 影响范围 (Impact)
- 受影响的模块：无
- 受影响的代码：
  - `pubspec.yaml`
  - `android/app/src/main/AndroidManifest.xml`
  - `lib/main.dart`
  - `lib/encryption/encryption_page.dart` (新建文件)

## 新增需求 (ADDED Requirements)
### 需求：动态权限请求
系统应当仅在用户点击选择文件或文件夹按钮时，才请求存储权限（针对 Android 11+ 请求 `MANAGE_EXTERNAL_STORAGE`，旧版本请求 `READ/WRITE_EXTERNAL_STORAGE`），禁止在应用启动时请求。

#### 场景：成功情况
- **当 (WHEN)** 用户首次点击“选择文件”或“选择文件夹”按钮时
- **则 (THEN)** 系统提示获取存储权限或所有文件访问权限
- **当 (WHEN)** 权限被授予后
- **则 (THEN)** 系统打开文件选择器

### 需求：文件与文件夹选择
系统应当允许用户调用系统文件选择器来选择单个文件或文件夹，并在屏幕上显示所选路径，以便为后续的加密功能做好准备。

#### 场景：成功情况
- **当 (WHEN)** 用户选择了文件或文件夹后
- **则 (THEN)** UI 更新，美观地展示所选路径。
