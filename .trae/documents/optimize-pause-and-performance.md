# 优化任务暂停逻辑与性能设置 UI 计划

## 摘要
本计划旨在修复并完善加密任务的递归暂停/恢复逻辑（防止已完成的任务被错误重置），在传输列表顶部增加醒目的“一键开始/暂停”全局按钮，并确认与完善“性能设置”中基于 CPU 核心数的多线程加密并发控制。

## 现状分析
1. **递归状态重置的 Bug**：目前的 `_updateStatusRecursive` 会盲目地将文件夹内所有子任务的状态重写。如果用户暂停一个文件夹，里面已经 `completed`（完成）的子文件会被错误地标记为 `paused`，随后点击恢复时会变成 `pending` 导致重复加密。
2. **全局按钮不明显**：当前“全部暂停/开始”功能仅仅是面板标题栏右上角的一个小图标，不符合用户要求的“传输列表的最上方，增加一个一键开始/暂停按钮”。
3. **多线程并发控制**：`PerformanceSettingsPage` 已经初步实现了 UI，但需要确保其默认值（CPU数量除以2）、最大值（CPU数量减1）完全符合要求，并且底层 `EncryptionTaskManager` 能正确根据该设置动态分配多线程并发数。

## 提出的更改

### 1. 修复任务递归状态更新逻辑
- **文件**: `lib/encryption/services/encryption_task_manager.dart`
- **操作**: 
  修改 `_updateStatusRecursive` 方法。在更新状态前增加拦截判断：
  - 如果目标状态是 `paused` 或 `pending`，且当前任务已经是 `completed`，则直接跳过该任务，不改变其状态。
  - 确保“暂停/取消”操作针对所有子目录和子文件准确生效，不会破坏已完成的进度。

### 2. 增加“一键开始/暂停”全局大按钮
- **文件**: `lib/encryption/encryption_page.dart`
- **操作**: 
  - 在 `EncryptionProgressPanel` 组件中，移除原先标题栏右上角的 Icon 按钮。
  - 在 `ListView.builder` 的上方（或列表的第 0 项），注入一个横向撑满的 `ElevatedButton.icon`。
  - **逻辑**：当 `manager.hasActiveTasks` 为 true 时，按钮显示“一键全部暂停”，点击调用 `pauseAll()`；当所有任务都处于暂停（或无进行中任务但有等待中任务）时，按钮显示“一键全部开始”，点击调用 `resumeAll()`。

### 3. 完善“性能设置”并发数配置
- **文件**: `lib/encryption/performance_settings_page.dart` & `lib/encryption/services/encryption_task_manager.dart`
- **操作**:
  - 审查并巩固 `_PerformanceSettingsPageState`：确认最小值为 1，最大值为 `Platform.numberOfProcessors - 1`，首次默认值为 `Platform.numberOfProcessors ~/ 2`。
  - 确保拖动 Slider 或输入框修改后，不仅存入 `SharedPreferences`，还能实时通知 `EncryptionTaskManager` 更新 `_maxWorkers`，使得正在排队的任务能立即应用新的并发数。

### 4. 增加“关于”页面的版本同步与更新日志展示
- **文件**: `lib/main.dart` 或 `lib/settings/about_page.dart` (如果存在)，以及 `.trae/rules.md`
- **操作**:
  - 在工作区的规则文件 `.trae/rules.md` 中写入新的发版规则：“每次更新版本时，必须同步更新应用内‘关于’页面的版本号，并在其中展示最新的版本更新记录（Changelog）。”
  - 完善应用内的 `AboutPage`：读取 `pubspec.yaml` 自动显示当前版本，并从本地资源加载 `CHANGELOG.md` 或硬编码最新日志，实现应用内版本记录同步展示。

### 5. 规范化内部与外部私有目录（全中文分类）
- **文件**: `lib/cloud_drive/webdav_storage.dart`, `lib/error_reporter.dart`, `lib/encryption/services/encryption_task_manager.dart`, `lib/settings/theme_settings_page.dart`
- **操作**:
  - **内部私有目录** (`getApplicationDocumentsDirectory()` / `data/data/...`)：
    - `webdav_configs.json` 移动/改名至 `应用配置/webdav_configs.json`。
    - （确认已实施）`encryption_queue.json` 改名至 `加密任务记录/queue.json`。
    - （确认已实施）`backgrounds/` 改名至 `主题背景/`。
  - **外部私有目录** (`getExternalStorageDirectory()` / `0/android/data/...`)：
    - 将 `debug/~.txt` 错误日志路径重构为 `运行日志/错误日志.txt`。
  - 所有更改将只针对新文件的创建路径进行更新，如果原有文件存在，旧数据将保留（或可安全忽略，因为它们只是缓存/配置）。

## 假设与决策
- **决策**：多线程加密的每个文件占用一个 Isolate，并发数直接映射到 Isolate 的最大数量。当用户调低并发数时，已经运行的 Isolate 不会被强杀，而是等待其自然完成，之后不再分配新任务直到活跃数低于新的上限。
- **决策**：为了让“关于”页面能自动读取更新日志，将 `CHANGELOG.md` 注册为 Flutter 的 assets，在页面初始化时读取，以实现版本说明的“自动同步”。

## 验证步骤
1. **测试递归暂停**：导入一个包含多个文件的文件夹，等待其中一两个文件完成后，点击文件夹的“暂停”按钮，再点击“继续”，验证已完成的文件是否保持 `completed` 状态，未完成的文件是否能正常继续。
2. **测试一键控制**：观察传输列表最上方的大按钮，点击“一键全部暂停”，确认所有任务停止且按钮文字变为“一键全部开始”；再次点击恢复任务。
3. **测试并发控制**：进入“性能设置”，将 CPU 数量拉满（最大值），观察后台是否同时启动多个文件加密；将其调为 1，观察是否变为严格的单文件排队处理。
4. **测试“关于”页面**：进入应用的“关于”页面，检查是否正确显示当前版本号（如 v1.3.5）并完整展示更新日志。