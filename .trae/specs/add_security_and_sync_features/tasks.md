# Tasks
- [x] Task 1: 创建设置页"安全"模块 UI 及交互
  - [x] SubTask 1.1: 在设置页导航栏新增"安全"入口，创建新的安全设置页面。
  - [x] SubTask 1.2: 实现安全页面的临时状态管理（未保存时显示"确认"按钮，未保存退出时弹窗拦截与回滚）。
  - [x] SubTask 1.3: 实现权限模式选择 UI（普通模式 / Root 模式）。
  - [x] SubTask 1.4: 实现 Root 权限检测与申请逻辑，以及切换 Root 模式时的"默认"和"始终"行为选择框。
- [x] Task 2: 创建首页文件统计面板
  - [x] SubTask 2.1: 在首页添加文件统计区块 UI（本地加密文件数量、云端加密文件数量、差异文件数量及刷新按钮）。
  - [x] SubTask 2.2: 实现差异计算逻辑（结构对比与哈希对比）。
  - [x] SubTask 2.3: 在设置中增加"每次 App 启动时自动刷新"的配置项，并实现对应的启动自动触发逻辑。
- [x] Task 3: 改造索引文件规范与同步逻辑
  - [x] SubTask 3.1: 实现 `local_index.json` 的更新逻辑，在本地加密文件后记录文件名、结构和哈希值。
  - [x] SubTask 3.2: 实现 `remote_index_cache.json` 的下载、创建、修改及上传覆盖流程。
  - [x] SubTask 3.3: 实现云端上传前的一致性校验流程（哈希对比及冲突提示框）。

# Task Dependencies
- [Task 2] depends on [Task 3]

# Pending Fixes
- [x] Task 4: 修复一致性校验提示框问题
  - [x] SubTask 4.1: 在同步逻辑发生一致性校验失败（哈希不一致）时，捕获异常并向 UI 传递状态。
  - [x] SubTask 4.2: 在 UI 层（如 `WebDAVStateManager` 或设置弹窗）展示同步冲突提示框。
  - [x] SubTask 4.3: 完善 `lib/cloud_drive/webdav_new/sync_engine.dart` 与 UI 层的对接，替换掉占位代码。
