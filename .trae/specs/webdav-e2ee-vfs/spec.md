# WebDAV End-to-End Encrypted Virtual File System Spec

## Why
用户需要在基于 WebDAV 的云盘服务上实现端到端的透明加密虚拟文件系统，以确保云端只存储密文而无法获取明文信息。该功能优先支持 Android 平台，需提供类似于本地文件系统的完整读写体验（上传、浏览、打开、删除、改名），并能够流畅且安全地进行流式传输，保证大文件播放不卡顿。

## What Changes
- 实现 WebDAV 端到端加密虚拟文件系统，支持完整的读写操作（浏览、上传、打开、改名、删除）。
- 统一文件名与文件内容的加密算法：均采用相同的对称加密方案（如 AES-256-GCM），且使用同一套用户密钥。
- 严禁使用 Base64 作为加密手段，仅将其（如 Base64Url）用于密文等二进制数据的传输编码。
- 引入加密标识符（Encryption Marker）机制，支持目录树的加密状态向下递归继承。
- 实现分块下载（Chunked Download）与内存实时流式解密（Stream Decryption），文件内容明文不落盘。
- 将 CI/CD（GitHub Actions）的触发规则统一强制改为仅手动触发（`workflow_dispatch`），移除自动编译。

## Impact
- Affected specs: 云盘模块（WebDAV 客户端与预览机制）、加密模块。
- Affected code:
  - `lib/cloud_drive/`（WebDAV API、虚拟文件系统抽象、预览播放器）
  - `lib/encryption/`（AES-256-GCM 封装、文件分块加解密流）
  - `.github/workflows/`（工作流触发条件修改验证）

## ADDED Requirements
### Requirement: E2EE Virtual File System
系统需提供透明的加密文件系统操作，云端仅存储密文。
#### Scenario: Directory Browsing (Encrypted Domain)
- **WHEN** 用户浏览挂载的 WebDAV 目录，且目录或上级目录存在加密标识符时
- **THEN** 系统在内存中拉取并解密子文件名，构建虚拟目录树，此时不下载任何文件内容。

#### Scenario: Stream Opening Large Files
- **WHEN** 用户打开（如播放）加密的视频大文件时
- **THEN** 系统按需发起 Range 请求下载密文数据块（Chunk），在内存中实时进行 AES-256-GCM 解密并交付播放组件，明文全程不写入本地磁盘，不阻塞主应用线程。

### Requirement: Unified Encryption & Encoding
文件名与文件内容采用统一的 AES-256-GCM 加密，并共享同一套用户密钥。
#### Scenario: Filename Upload
- **WHEN** 用户上传新文件到加密目录时
- **THEN** 系统使用 AES-256-GCM 加密该文件名，并将得到的二进制密文及 Tag 进行 Base64(Url) 编码后作为云端对象名，确保单纯的 Base64 仅作为编码传输媒介。

## MODIFIED Requirements
### Requirement: CI/CD Workflow Triggers
将 GitHub Actions 的构建与发布工作流设定为纯手动触发。
**Reason**: 用户明确要求只能通过手动触发工作流（用于主动编译或排查错误），避免任何自动流水线运行。
**Migration**: 确保 `build.yml` 和 `release.yml` 的 `on:` 节点仅保留 `workflow_dispatch`，移除 `push`、`pull_request` 和 `tags` 等触发器。
