# Changelog

## 1.0.1 (2026-04-16)

### ✨ Features
- 新增：云盘页引入完整的 WebDAV 配置管理功能（增、删、改、查）。
- 新增：根据 Android 设备硬件级密钥存储能力自动检测安全等级（Level 1 / Level 2），并提供图形化警告提示。
- 新增：配置本地持久化能力，非敏感字段存储至 JSON，密码凭证保存于 Flutter Secure Storage 安全容器。

### 🐛 Bug Fixes
- 修复：解决主题切换时，底部导航栏中“设置”页面的主题选项按钮状态未即时刷新的问题。
- 修复：解决 Android 生产构建打包时，无法正确读取 GitHub Actions Secrets（`KEY_STORE_BASE64`, `KEY_ALIAS`, `KEY_PASSWORD`, `STORE_PASSWORD`）并执行生产签名的问题，确保更新后的 APK 签名一致以支持覆盖安装。

### 🛠 Build & CI
- 变更：优化 GitHub Actions 打包工作流，强制拦截无签名构建流程。

---

## 1.0.0
- 初始版本发布，搭建基础 Flutter 项目框架及基础的错误拦截体系。
