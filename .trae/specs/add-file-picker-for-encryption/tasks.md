# 任务列表 (Tasks)

*(注：由于之前的 WebDAV 云盘配置管理功能已全部实现并在 v1.0.1 中发布，故根据指示已将已完成的旧任务删除，以下为当前正在进行的加密页面文件选择器新任务。)*

- [x] 任务 1：添加依赖与声明完整权限
  - [x] 子任务 1.1：在 `pubspec.yaml` 中添加 `file_picker` 和 `permission_handler` 依赖
  - [x] 子任务 1.2：在 `android/app/src/main/AndroidManifest.xml` 中补充完整的 Android 权限声明：`<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />`、`<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />` 以及适配 Android 11+ 的 `<uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE" />`
- [x] 任务 2：实现高兼容性的权限请求与系统调用
  - [x] 子任务 2.1：创建 `lib/encryption/encryption_page.dart` 并包含有状态的组件 `EncryptionPage`
  - [x] 子任务 2.2：在 `EncryptionPage` 中实现**兼容性权限请求逻辑**：当 Android 11 及以上时请求 `Permission.manageExternalStorage`，当 Android 10 及以下时请求 `Permission.storage`。并确保**仅在点击按钮时请求**，启动时不弹窗
  - [x] 子任务 2.3：在获取相应权限后，使用 `file_picker` 实现文件选择和文件夹选择逻辑
- [x] 任务 3：构建美观 UI 并适配主题
  - [x] 子任务 3.1：在 `EncryptionPage` 中构建包含选择文件、选择文件夹按钮和所选路径展示区的 UI
  - [x] 子任务 3.2：确保 UI 完美适配现有的“默认”和“赛博朋克”两种主题
- [x] 任务 4：集成到主导航栏
  - [x] 子任务 4.1：将 `lib/main.dart` 中的占位符 `_TitlePage(title: '加密')` 替换为新编写的 `EncryptionPage`
