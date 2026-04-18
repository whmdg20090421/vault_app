# 移除加密逻辑准备重构 Spec

## Why
当前的加密业务逻辑（包括任务队列管理、VFS 层面的读写代理等）存在问题或者需要整体重新设计。为了方便后续的全部重构，需要将现有的加密业务逻辑予以清除，同时**保留**基础的加密算法实现以及前端界面的 UI 结构，使得重构能够在干净的逻辑基座上开展而不丢失已有的界面和底层算法工具。

## What Changes
- **保留算法与 UI**：
  - 完整保留 `lib/encryption/crypto/` 下的所有加密算法（如 `chunk_crypto.dart` 等）。
  - 完整保留 `lib/encryption/` 下所有单纯负责 UI 展示的页面和组件（如 `encryption_page.dart`, `vault_explorer_page.dart` 等）。
- **清理加密逻辑**：
  - 删除或清空 `lib/encryption/services/encryption_task_manager.dart` 中的任务队列调度与执行逻辑，仅保留能让程序编译通过的类名与空壳方法。
  - 删除或清空 `lib/vfs/encrypted_vfs.dart` 中绑定加密和虚拟文件系统的具体读写代理逻辑，保留空实现使得接口仍然存在。
  - 移除 UI 页面（如 `vault_explorer_page.dart`）中发起具体加密流程（如 `doImportFileIsolate`, `_importFolder` 等）的代码实现，仅保留按钮和交互的空壳响应。
  - **BREAKING**: 原有的加密、解密任务执行能力将暂时失效，直到重构完成。

## Impact
- Affected specs: 加密任务调度、加密文件导入/导出。
- Affected code:
  - `lib/encryption/services/encryption_task_manager.dart`
  - `lib/vfs/encrypted_vfs.dart`
  - `lib/encryption/vault_explorer_page.dart`

## REMOVED Requirements
### Requirement: 现有加密调度与隔离线程导入逻辑
**Reason**: 用户明确要求删除所有加密逻辑，保留 UI 和算法，为全部重构做准备。
**Migration**: 暂不提供替代方案。后续重构中将基于现有的 UI 和底层算法重新实现。
