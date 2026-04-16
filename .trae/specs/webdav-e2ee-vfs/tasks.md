# Tasks

- [ ] Task 1: 工作流与加密基础规范确认
  - [ ] SubTask 1.1: 验证并确保 `.github/workflows/build.yml` 和 `release.yml` 已完全修改为仅 `workflow_dispatch` 手动触发。
  - [ ] SubTask 1.2: 在 `lib/encryption/utils/` 中封装 AES-256-GCM 算法，统一提供给文件名与文件内容加解密使用（保证使用相同的用户密钥）。
  - [ ] SubTask 1.3: 封装 Base64Url 编解码工具函数，明确其仅用于密文二进制数据的字符串传输编码。

- [ ] Task 2: 加密标识符（Marker）与虚拟文件系统架构
  - [ ] SubTask 2.1: 定义 WebDAV VFS 抽象层（支持 List、Open、Stat、Upload、Delete、Rename）。
  - [ ] SubTask 2.2: 实现加密标识符（Marker）的生成与云端探测逻辑，支持目录遍历时的加密域状态缓存与向下递归继承。

- [ ] Task 3: 目录与文件名级别的读写操作（浏览、改名、删除）
  - [ ] SubTask 3.1: 浏览（Browse）：实现 PROPFIND 拉取文件列表，并在内存中解密文件名（Base64Url 解码 -> AES-256-GCM 解密），构建透明的虚拟目录树。
  - [ ] SubTask 3.2: 改名（Rename）：对新名称执行相同的加密编码流程，并调用 WebDAV MOVE 更新云端对象。
  - [ ] SubTask 3.3: 删除（Delete）：直接对密文文件/目录对象调用 WebDAV DELETE。

- [ ] Task 4: 文件内容分块加密与流式读写（上传、打开）
  - [ ] SubTask 4.1: 上传（Upload）：实现按固定块大小（Chunk）读取本地明文文件，逐块执行 AES-256-GCM 加密，并以流式或分段 PUT 写入 WebDAV 云端。
  - [ ] SubTask 4.2: 打开/播放（Open/Read）：实现基于 HTTP Range 请求的按需分块下载逻辑（Chunked Download）。
  - [ ] SubTask 4.3: 内存流式解密：在内存中实时解密获取到的 Chunk 密文，并无缝交付给上层组件（如媒体播放器或流读取器），确保明文数据绝对不落盘。

# Task Dependencies
- Task 2 depends on Task 1
- Task 3 depends on Task 2
- Task 4 depends on Task 2 and Task 3
