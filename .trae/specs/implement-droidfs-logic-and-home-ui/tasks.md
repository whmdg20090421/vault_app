# Tasks

- [x] Task 1: 仿 DroidFS 加密逻辑（重构/新增 `vfs` 及 `chunk_crypto`）
  - [x] SubTask 1.1: 实现目录结构映射（1对1）及文件名确定性加密逻辑（如使用 AES 结合父路径哈希或固定 IV，将结果进行 Base64Url 编码）。
  - [x] SubTask 1.2: 实现单文件完整加密/解密流：文件头部包含随机 File ID (16 bytes)，文件内容分块（如 64KB），Nonce 使用 File ID + 块序号动态派生。
  - [x] SubTask 1.3: 引入多线程处理（Isolate / compute）以支持并发加解密多文件或大文件块操作。
  
- [x] Task 2: 实现真实数据扫描与缓存服务 (`StatsService`)
  - [x] SubTask 2.1: 创建 `StatsService` 类，提供扫描本地加密目录和未加密缓冲目录的方法，返回总字节数。
  - [x] SubTask 2.2: 使用 `shared_preferences` 缓存扫描结果。App 启动时直接读取缓存，并在需要时（如同步后、加密完成）才触发重新扫描。
  - [x] SubTask 2.3: 添加单位自动换算方法（小于 1GB 返回 MB，大于等于 1GB 返回 GB）。
  
- [x] Task 3: 调整主页数据概览 UI 布局并绑定真实数据
  - [x] SubTask 3.1: 将 `HomePage` 中的卡片布局改为左右横向结构（`Row`），左侧 `Expanded(flex: 1)` 内放置正方形卡片。
  - [x] SubTask 3.2: 右侧 `Expanded(flex: 1)` 留白或预留容器。
  - [x] SubTask 3.3: 饼图（PieChart）绑定 `StatsService` 返回的真实数据缓存，格式化显示容量与百分比。
  - [x] SubTask 3.4: 增加下拉刷新（RefreshIndicator）或刷新按钮，用于手动触发重新计算并更新主页饼图。

- [x] Task 4: 优化保险箱解锁速度与补充功能
  - [x] SubTask 4.1: 分析保险箱解锁极慢（>1分钟）的原因。大概率是 KDF (Argon2id/Scrypt/PBKDF2) 计算在主线程且参数过高。使用 Isolate (如 `compute()`) 进行密码派生验证，避免阻塞主线程。
  - [x] SubTask 4.2: 调整创建保险箱时的默认 KDF 参数，在保证安全的前提下控制派生耗时在合理范围（如 1-3 秒）。
  - [x] SubTask 4.3: 在保险箱内部的浏览页面补充“添加文件夹” (新建目录) 的基础功能按钮，支持通过新建目录来管理密文空间。
