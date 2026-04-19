# 加密文件处理模块 V4 重构 Spec

## Why
原有的加密逻辑已被清理，现需要基于最新完整版 V4 需求重构核心加密流与进度展示。新架构要求极高的进度透明度、细粒度的层级树状任务控制（参考 Cryptomator），以及高性能的并发加密和动态 UI 刷新机制，以解决历史版本中任务状态混乱、进度计算不准确等痛点。

## What Changes
- **文件树与模型重建**：重新设计 `EncryptionNode` (包含 FileNode/FolderNode)，使用严格的枚举状态 (`pending_waiting`, `pending_paused`, `encrypting`, `completed`, `error`)，并实现持久化。
- **多线程加密引擎**：引入基于预设线程数并发执行的加密调度器，根据节点状态和 `isPaused` 标志自动拉取任务，遇到缺失或损坏文件自动标记 `error` 而不阻塞主流程。
- **导航栏总览进度**：主页顶部新增四色进度条（绿、黄、红、灰），严格遵守最小 1% (1像素) 的强制可视化显示规则。
- **层级进度详情弹窗**：新增自下而上的半屏模态框，展示所有活跃根节点及其展开子树。提供三行紧凑布局（控制按钮+名称、四色细管进度、百分比与数量统计）。
- **节点级控制**：支持任意层级节点的暂停/继续（影响其下所有子树）及长按移除任务/标记已修复功能。
- **动态刷新机制**：建立前后台分离的监听线程。前台高频刷新（0.5~1秒），后台静默刷新（5~10秒），无活跃任务时冻结刷新并缓存最终进度。
- **任务归档与后处理**：任务100%完成后检查实体文件存在性，无误则移入历史记录；加密完成的文件需自动计算哈希并计入 `local_index.json`。

## Impact
- Affected specs: 加密任务调度核心、加密进度 UI 展示、文件导入处理流、主页导航栏。
- Affected code:
  - `lib/encryption/models/encryption_node.dart` (新增)
  - `lib/encryption/services/encryption_task_manager.dart` (重写)
  - `lib/encryption/vault_explorer_page.dart` (重写导入逻辑)
  - `lib/home/home_page.dart` (修改导航栏)
  - `lib/encryption/widgets/encryption_progress_modal.dart` (新增)

## ADDED Requirements
### Requirement: 细粒度层级状态树
系统必须将每次导入操作转化为独立的根节点，递归生成文件树，并精确维护每个子节点的加密状态和字节进度。
#### Scenario: 导入嵌套文件夹
- **WHEN** 用户导入包含多个子目录的文件夹
- **THEN** 系统解析为包含 `FolderNode` 和 `FileNode` 的树结构，持久化存储，初始状态为 `pending_waiting`。

### Requirement: 动态自适应刷新机制
系统必须在节省资源与提供即时反馈间取得平衡。
#### Scenario: 前后台切换
- **WHEN** 用户打开查看进度详情弹窗
- **THEN** 刷新率切换为 0.5~1秒/次；关闭弹窗且无其他可见进度UI时，降为 5~10秒/次。

### Requirement: 节点级管控
用户可以干预正在进行的加密流程。
#### Scenario: 暂停某子文件夹
- **WHEN** 用户在进度详情中点击某子文件夹的“暂停”按钮
- **THEN** 该文件夹及其所有子节点的正在执行的加密线程被终止，状态变更为 `pending_paused`。

## MODIFIED Requirements
### Requirement: 多线程加密执行
重写 `EncryptionTaskManager` 以支持按需拉取、断点异常隔离和多线程并发加密。

## REMOVED Requirements
### Requirement: 旧版扁平化任务队列
**Reason**: 无法满足 V4 规范中“同级关系、嵌套展开”及层级暂停的需求。
**Migration**: 废弃原扁平列表，改用 `List<EncryptionNode>` 树状结构。
