# Tasks

- [ ] Task 1: 基础 WebDAV 客户端与文件浏览器架构搭建（UI & Client）
  - [ ] SubTask 1.1: 引入或封装 WebDAV 客户端通信逻辑，支持标准 WebDAV 协议（PROPFIND, GET, PUT, MKCOL, DELETE, MOVE）。
  - [ ] SubTask 1.2: 开发 WebDAV 文件浏览器 UI（`webdav_browser_page.dart`），实现面包屑路径导航、文件/目录列表展示、以及加载状态管理。
  - [ ] SubTask 1.3: 在 UI 中接入基础操作交互入口：悬浮按钮（上传文件、新建文件夹）、列表项菜单（删除、重命名）。

- [ ] Task 2: 虚拟文件系统（VFS）抽象与加密算法封装
  - [ ] SubTask 2.1: 定义 VFS 接口层（支持 List、Open、Stat、Upload、Delete、Rename），将 UI 层的操作全部代理到 VFS 层。
  - [ ] SubTask 2.2: 在 `lib/encryption/utils/` 中封装统一的 AES-256-GCM 算法（复用密码派生的 MasterKey，支持按 Chunk 加解密）。
  - [ ] SubTask 2.3: 封装 Base64Url 编解码工具函数，明确其仅用于密文二进制数据的字符串传输编码。

- [ ] Task 3: 加密标识符（Marker）与目录/文件名透明加解密逻辑
  - [ ] SubTask 3.1: 实现加密标识符（Marker）的生成与云端探测逻辑，支持目录遍历时的加密域状态缓存与向下递归继承。
  - [ ] SubTask 3.2: 浏览（Browse）：VFS 拦截 PROPFIND 结果，如果在加密域，则将 Base64Url+AES 密文文件名在内存中解密为明文展示。
  - [ ] SubTask 3.3: 目录/文件操作（Rename/Delete/Mkdir）：VFS 自动对新名称进行加密编码，并调用 WebDAV 执行。

- [ ] Task 4: 文件内容分块加密与流式读写（上传、打开）
  - [ ] SubTask 4.1: 上传（Upload）：实现按固定块大小（Chunk）读取本地明文文件，逐块执行 AES-256-GCM 加密，并以流式或分段 PUT 写入 WebDAV 云端。
  - [ ] SubTask 4.2: 打开/播放（Open/Read）：实现基于 HTTP Range 请求的按需分块下载逻辑（Chunked Download）。
  - [ ] SubTask 4.3: 内存流式解密：在内存中实时解密获取到的 Chunk 密文，并无缝交付给上层组件（如媒体播放器或流读取器），确保明文数据绝对不落盘。

- [ ] Task 5: 工作流触发规则验证
  - [ ] SubTask 5.1: 验证并确保 `.github/workflows/build.yml` 和 `release.yml` 已完全修改为仅 `workflow_dispatch` 手动触发。

# Task Dependencies
- Task 2 depends on Task 1
- Task 3 depends on Task 2
- Task 4 depends on Task 3
