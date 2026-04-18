# 安全与同步功能增强 Spec

## Why
当前应用缺乏集中的安全权限管理（如 Root 模式）、加密与同步状态的直观统计面板，以及清晰规范的本地与云端索引文件一致性维护流程。为了提升用户对应用安全性的控制感，并且让用户能够清晰掌握本地与云端加密文件的差异和同步状态，需要对这些模块进行功能增强。

## What Changes
- 在设置页新增"安全"模块，支持配置临时状态与未保存退出提示，并支持 Root 权限模式的选择（普通、Root-默认、Root-始终）。
- 在首页新增文件统计面板，展示本地加密文件数、云端加密文件数以及差异文件数，支持手动或启动时自动刷新差异计算。
- 引入新的索引文件规范（`local_index.json`, `remote_index.json`, `remote_index_cache.json`），规范本地更新、云端上传、差异计算及上传前的一致性校验流程。

## Impact
- Affected specs: 设置页权限管理、首页数据展示、云端同步逻辑、本地加密记录。
- Affected code: 
  - `lib/settings/settings_page.dart` (或相关设置页面)
  - `lib/home/home_page.dart` (或相关主页页面)
  - `lib/services/sync_storage_service.dart`
  - `lib/encryption/services/encryption_task_manager.dart`

## ADDED Requirements
### Requirement: 设置页安全模块
系统应当提供一个独立的"安全"设置页，允许用户配置权限模式。

#### Scenario: 未保存退出
- **WHEN** 用户修改了权限配置但未点击保存按钮，尝试返回上一页
- **THEN** 弹出提示框："当前设置未保存，是否退出？"，提供"退出"和"继续编辑"选项。如果选择退出，则UI控件视觉上回滚为上次保存的值，且不应用新配置。

#### Scenario: 切换 Root 模式
- **WHEN** 用户尝试将权限模式切换为 Root 模式
- **THEN** 系统立即检测是否已授予 Root 权限。若未授予，则发起授权申请；若授权失败，显示报错信息，且"确认"按钮置灰不可用。如果注册成功，则在下方弹出 Root 行为选择框（默认 / 始终）。

### Requirement: 首页文件统计面板
系统应当在首页提供文件数量统计与差异显示。

#### Scenario: 刷新差异
- **WHEN** 用户点击差异数量旁边的刷新按钮，或在设置中开启了自动刷新且 App 启动时
- **THEN** 系统触发差异计算逻辑，从云端下载 `remote_index.json` 作为缓存，对比本地 `local_index.json`，统计并显示结构差异和哈希差异的文件总数。

### Requirement: 索引文件规范与一致性校验
系统应当遵循明确的索引文件命名与同步职责，并在每次上传前进行一致性校验。

#### Scenario: 上传前的一致性校验
- **WHEN** 准备将文件上传至云端前
- **THEN** 从云端下载当前的 `remote_index.json` 并计算哈希，对比本地缓存的 `remote_index_cache.json`。若不一致，提示用户是否将本地缓存同步至云端。

## MODIFIED Requirements
### Requirement: 本地加密更新索引
- **WHEN** 在本地对文件进行加密操作后
- **THEN** 同步更新 `local_index.json`，记录加密后的文件名、目录结构和哈希值。
