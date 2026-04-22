# Enhance Encryption UX and Compatibility Test Spec

## Why
修复长按“关于”键无法进入开发者模式的问题，优化加密进度条中文件夹的加密模式标签显示，改进加密界面的新建交互，并在性能设置中增加底层加密兼容性与速度测试，从而提升整体用户体验和调试能力。

## What Changes
- 修复设置页“关于”选项长按 5 秒无法触发开发者模式弹窗的 Bug。
- 修改加密进度条的 UI 逻辑，使文件夹也能显示其子文件/子文件夹所分配的加密模式（硬件加密/普通加密）。
- 更改加密界面的“+”号悬浮按钮点击逻辑，点击后弹出一个底部菜单或下拉列表，列表的第一项为“创建加密文件夹”，其他项可保留原有的选择文件/文件夹功能。
- 在“设置 -> 性能设置”中新增“兼容性测试”功能，点击后可分别测试底层硬件加密与普通软件加密的可用性及大致的加密速度。

## Impact
- Affected specs: 设置页交互、加密列表 UI 展示、悬浮按钮交互、性能设置页。
- Affected code: 
  - `lib/settings/vault_config_page.dart` (关于选项的长按事件及性能设置项)
  - `lib/encryption/widgets/encryption_progress_panel.dart` (文件夹的加密模式展示)
  - `lib/encryption/screens/encryption_screen.dart` (或负责加号按钮的对应页面)

## ADDED Requirements
### Requirement: 悬浮按钮弹出菜单
当用户在加密界面点击加号时，不应直接调用系统文件选择器，而是弹出一个操作列表。
#### Scenario: 成功展示菜单
- **WHEN** 用户点击加密界面的“+”号按钮
- **THEN** 弹出一个包含“创建加密文件夹”、“导入文件”等选项的列表。

### Requirement: 兼容性与速度测试
在性能设置中增加兼容性测试功能，以评估硬件与软件加密的状态。
#### Scenario: 执行兼容性测试
- **WHEN** 用户在性能设置中点击“兼容性测试”
- **THEN** 系统分别运行硬件和软件加密的小型基准测试，并显示测试结果（是否可用、预估加密速度）。

## MODIFIED Requirements
### Requirement: 开发者模式入口修复
长按“关于”选项 5 秒必须能够正确触发进入开发者模式的警告弹窗。

### Requirement: 文件夹加密模式标签
文件夹节点在加密列表中不仅要显示进度，还需汇总展示其子任务所使用的加密模式（例如同时显示硬件和软件加密的标签）。

## REMOVED Requirements
无
