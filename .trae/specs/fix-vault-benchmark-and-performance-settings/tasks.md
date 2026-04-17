# Tasks

+ [x] Task 1: 复现并定位“创建并保存”卡死原因
  + [x] SubTask 1.1: 梳理 VaultConfigPage 保存流程（KDF 派生/验证块生成/写入 JSON/更新 SharedPreferences）
  + [x] SubTask 1.2: 识别阻塞 UI 的同步计算点，并确定迁移到后台执行的最小改动方案

+ [x] Task 2: 修复保存流程卡死（后台计算 + UI 状态）
  + [x] SubTask 2.1: 将 KDF 派生与验证块生成迁移到 isolate 执行（保持参数可序列化、无 UI 依赖）
  + [x] SubTask 2.2: 保存期间保持按钮禁用与加载状态展示，完成后恢复状态并提示结果

+ [x] Task 3: 修复 Benchmark 进度溢出问题
  + [x] SubTask 3.1: 将进度计算改为基于“实际处理量”的计算方式（例如 bytesProcessed/totalBytes），并对进度进行 clamp
  + [x] SubTask 3.2: 覆盖异常/取消/失败场景，确保进度与状态正确复位

+ [x] Task 4: Benchmark 多线程（多 isolate 并行）
  + [x] SubTask 4.1: 设计 worker 协议：输入 chunk 索引/算法/nonce 派生规则/密钥，输出耗时与已处理字节数
  + [x] SubTask 4.2: 实现并行执行与汇总测速（MB/s），并与进度条联动
  + [x] SubTask 4.3: 保持内存安全（不一次性加载 500MB），并确保测试结束清理临时资源

+ [x] Task 5: 增加“性能设置”页面与入口
  + [x] SubTask 5.1: 在性能测试相关 UI 后增加“性能设置”入口（与现有赛博朋克主题一致）
  + [x] SubTask 5.2: 实现核心数量配置 UI：显示“(当前可使用/系统总核心数)” + Slider + 输入框联动
  + [x] SubTask 5.3: 实现输入约束：1 <= cores <= (maxCores - 1)，并持久化到 SharedPreferences

+ [x] Task 6: 验证与回归
  + [x] SubTask 6.1: 确认创建并保存不再触发卡死（PBKDF2 高迭代、Scrypt、Argon2id）
  + [x] SubTask 6.2: 确认 Benchmark 进度不超过 100%，完成时稳定为 100%
  + [x] SubTask 6.3: 确认 Benchmark 多核生效（CPU 使用率分布改善），且结果可正常展示

# Task Dependencies
- Task 2 depends on Task 1
- Task 4 depends on Task 3
- Task 6 depends on Task 2, Task 4, Task 5

