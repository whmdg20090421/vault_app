# Implement DroidFS-like Logic and Home UI Spec

## Why
当前应用的加密实现较为基础且主页的统计数据为硬编码假数据。为了增强文件加密的安全性与性能（仿照 DroidFS/gocryptfs 的一比一目录映射、分块流式加密及确定性文件名加密，并支持多线程），同时将主页数据概览升级为包含缓存机制的真实统计模块，需对这两大模块进行重构与完善。

## What Changes
- **DroidFS 加密文件管理逻辑复刻（Dart/Flutter 原生实现）**
  - **虚拟文件系统目录结构映射**：明密文目录结构保持 1:1 映射（即明文子目录直接对应密文子目录），便于增量同步。
  - **文件名加密方式**：使用确定性加密（如 AES-SIV 或结合固定上下文的 AES-GCM）对文件名加密并 Base64Url 编码，确保相同路径下的同名文件加密后名称一致；若加密后文件名过长（>255字节），则截断或哈希处理。
  - **文件加解密完整流程（含多线程）**：引入基于块（如 4KB/64KB）的流式加密，文件头部存储随机 File ID，数据块 Nonce 由 File ID 与 Block Number 派生；针对多文件及大文件加解密，引入 Dart `Isolate` 或并发队列以仿照 DroidFS 的多线程处理能力。
- **主页数据概览 UI 调整**
  - 将主页布局改为左右横向结构，左半部分放置正方形数据概览卡片，右半部分留空。
- **主页数据真实化与缓存机制**
  - **统计扫描**：扫描本地保险箱目录（已加密）与待处理目录（尚未加密、失败、暂停的文件），计算总体积。
  - **持久化缓存**：将统计结果序列化至 `SharedPreferences`（或本地 JSON），App 启动时直接读取缓存，不触发全盘扫描。
  - **触发更新**：仅在以下情况重新扫描并更新缓存：
    1. 文件加解密任务完成时
    2. 发生 WebDAV 云端同步时
    3. 用户手动触发（下拉刷新或点击刷新按钮）
  - **动态单位换算**：小于 1GB 格式化为 MB，大于等于 1GB 格式化为 GB。

## Impact
- Affected specs: 核心加解密模块（EncryptedVFS）、文件操作服务、主页视图（HomePage）、数据统计服务。
- Affected code: 
  - `lib/vfs/` 下的核心加密逻辑文件（如 `encrypted_vfs.dart`，`chunk_crypto.dart`）。
  - `lib/home_page.dart` UI 布局及状态管理。
  - 新增 `lib/services/stats_service.dart` 用于缓存与真实数据扫描。

## ADDED Requirements
### Requirement: DroidFS-like 加密逻辑实现
系统 SHALL 提供类似于 DroidFS (gocryptfs) 的文件级加解密体系，包含 1:1 目录映射、文件名确定性加密、基于块的流式内容加解密（随机 File ID + Block Num 派生 Nonce），以及多文件/大文件的并发处理（Isolate）。

### Requirement: 真实数据扫描与缓存
系统 SHALL 提供 `StatsService` 来获取“已加密”与“未加密”文件的总体积，将结果缓存至本地存储，并在 App 启动时极速加载。

#### Scenario: 重新扫描统计
- **WHEN** 用户手动刷新，或文件加解密成功，或 WebDAV 同步完成
- **THEN** 系统在后台线程扫描指定目录，更新体积结果，保存至缓存，并通知主页饼图刷新。

## MODIFIED Requirements
### Requirement: 主页布局调整
主页概览卡片 SHALL 调整为占据左侧 1/2 宽度的正方形卡片，饼图数据绑定真实的缓存统计结果，右侧留空以备后续扩展。
