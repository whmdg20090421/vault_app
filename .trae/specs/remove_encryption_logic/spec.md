# 移除加密逻辑准备重构 Spec

## Why
当前的加密业务逻辑（包括任务队列管理、加密核心流处理等）存在问题或者需要整体重新设计。为了方便后续的全部重构，需要将现有的实际加密逻辑予以清除，同时**保留**基础的加密算法实现、前端界面的 UI 结构以及像虚拟映射层（VFS）这样的设计思路和骨架，使得重构能够在干净的逻辑基座上开展而不丢失已有的界面和底层算法工具。

## What Changes
- **保留算法与 UI**：
  - 完整保留 `lib/encryption/crypto/` 下的所有加密算法（如 `chunk_crypto.dart` 等）。
  - 完整保留 `lib/encryption/` 下所有单纯负责 UI 展示的页面和组件（如 `encryption_page.dart`, `vault_explorer_page.dart` 等）。
- **保留架构设计思路（VFS与映射层）**：
  - 保留 `lib/vfs/` 下虚拟文件系统的结构和定义（包括 `encrypted_vfs.dart`），但不删除方法，仅清理其中**实际负责加解密读写**的具体核心逻辑。
- **清理实际加密执行逻辑**：
  - 清空 `lib/encryption/services/encryption_task_manager.dart` 中的任务执行与文件流处理具体实现（如隔离线程、流转换），仅保留队列的骨架结构以备重构。
  - 清空 UI 页面（如 `vault_explorer_page.dart`）中发起具体加密流程（如 `doImportFileIsolate`, `_importFolder` 等）的实际加密代码实现，仅保留按钮响应和架构思路的空壳。
  - **BREAKING**: 原有的具体加密、解密任务执行能力将暂时失效，等待重构。

## Impact
- Affected specs: 实际的加密和解密文件流处理。
- Affected code:
  - `lib/encryption/services/encryption_task_manager.dart`
  - `lib/encryption/vault_explorer_page.dart`
  - `lib/vfs/encrypted_vfs.dart` (仅清理具体加密读写逻辑，保留VFS结构)

## REMOVED Requirements
### Requirement: 现有实际加密流执行逻辑
**Reason**: 用户明确要求删除所有实际的加密逻辑，保留架构思路（VFS映射层）、UI和算法，为重构加密过程做准备。
**Migration**: 暂不提供替代方案。后续重构中将基于现有的 VFS 结构和底层算法重新实现。
