# 天眼·艨艟战舰 (Vault App)

这是一个端到端加密云盘与本地保险箱的 Flutter 应用。结合硬件级密钥存储与强一致性加密算法，提供最高规格的数据隐私保护。

## 最新版本概览

<!-- RELEASE_SUMMARY_START -->
- 当前版本：1.8.1
- **修复编译与打包失败问题**：修复了在上一版本重构 `SyncEngine` 与 `VfsFolderPickerDialog` 时引入的 Dart 语法错误与参数不匹配问题，彻底解决了 Github Actions 中 `Build APK` 阶段由于代码报错导致的流水线中断，确保了应用能够被成功编译与发布。
- 完整更新：https://github.com/whmdg20090421/vault_app/releases/tag/v1.8.1
<!-- RELEASE_SUMMARY_END -->

## 更新历史 (Changelog)

为了保持页面整洁，以下仅展示版本号与简要更新说明。点击版本号蓝色链接可查看极度详细的更新内容：

- [1.8.1](docs/changelogs/v1.8.1.md) - 修复 Dart 语法错误导致 Action `Build APK` 编译中断的 Bug。
- [1.8.0](docs/changelogs/v1.8.0.md) - 修复同步盲区与 ETag 比较问题，解决极端情况下的数据同步丢失与覆盖隐患。
- [1.7.0](docs/changelogs/v1.7.0.md) - 重构文件一致性校验机制（ETag），加入并发锁 (LOCK/UNLOCK) 控制，并引入基于 JSON 的全局配置与同步任务断点续传持久化管理。

- [1.2.3](docs/changelogs/v1.2.3.md) - 引入专业的 WebDAV 同步管理仪表盘（Dashboard），集成真实删除与同步差异比对引擎，清理冗余缓存。
- [1.2.2](docs/changelogs/v1.2.2.md) - 重构赛博朋克与纯黑主题，新增全局自定义图片背景，全面真实化数据概览与原生 WebDAV 底层通信。
- [1.1.4](docs/changelogs/v1.1.4.md) - 新增 WebDAV 云盘同步功能、后台多线程重试传输引擎与全局进度监控面板。
- [1.1.3](docs/changelogs/v1.1.3.md) - 底层加密核心架构重构（1:1目录映射、确定性文件名），大幅提升空保险箱解锁速度至秒级，新增主页缓存机制。
- [1.1.2](docs/changelogs/v1.1.2.md) - 引入 `fl_chart` 实现主页数据可视化，增强设置页与加密任务进度面板体验。
- [1.1.1](docs/changelogs/v1.1.1.md) - 修复部分重要 Bug，优化后台线程隔离计算，加强硬件基准测试（多核并行），重构云盘交互。
- [1.1.0](docs/changelogs/v1.1.0.md) - 核心本地保险箱上线，高自由度加密协议矩阵，明文配置导出，赛博朋克主题全面升级。
- [1.0.2](docs/changelogs/v1.0.2.md) - 集成原生文件选择器，适配 Android 11+ 动态存储权限，完善双轨主题。
- [1.0.1](docs/changelogs/v1.0.1.md) - 完善 WebDAV 生命周期管理，新增硬件安全等级检测与安全混合持久化存储方案。
- [1.0.0](docs/changelogs/v1.0.0.md) - 项目启航，完成基础架构与 UI 路由搭建。
