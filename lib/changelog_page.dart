import 'package:flutter/material.dart';

class ChangelogPage extends StatelessWidget {
  const ChangelogPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('更新日志'),
      ),
      body: ListView(
        children: const [
          ExpansionTile(
            title: Text('版本 1.1.4 (2026-04-16)'),
            children: [
              ListTile(
                title: Text(
                    '✨ Features & Sync Engine\n'
                    '• WebDAV 云盘同步功能：全面支持本地加密保险箱与 WebDAV 云端的双向文件同步。\n'
                    '• 智能同步策略配置：在新建同步任务时，提供向导式 UI。支持“自动匹配”功能自动在云端查找或创建对应的同名目录。同时支持用户自由选择同步方向（云端到本地、本地到云端）以及冲突处理策略（跳过、合并、覆盖）。\n'
                    '• 多线程无断点续传重试引擎：考虑到 WebDAV 网盘直传不支持断点续传的特性，在后台 Isolate 中独立构建了稳健的传输引擎。任何网络中断或残缺数据均会被直接丢弃并标记失败，重回队列。\n'
                    '• 严格的任务挂起熔断机制：针对恶劣网络环境，引入了熔断机制。单个文件连续 3 次传输失败将被永久挂起；整个任务中连续出现 10 个文件传输失败，则自动暂停整个同步任务，防止无效重试耗尽资源。\n'
                    '• 全局同步进度监控面板：在“云盘”界面的右上角与悬浮层新增了动态进度图标，点击可呼出底部面板。面板支持层级目录展开，实时显示文件数量、百分比进度，并提供“全部暂停”、“一键全部开启”以及单个挂起文件的“恢复”操作。'
                ),
              ),
            ],
          ),
          ExpansionTile(
            title: Text('版本 1.1.3 (2026-04-16)'),
            children: [
              ListTile(
                title: Text(
                    '✨ Features & Security\n'
                    '• 底层加密核心架构重构：深入参考了 DroidFS 的底层逻辑，用 Dart 原生完全重构了虚拟文件系统 (VFS) 的加密引擎。\n'
                    '• 目录结构 1:1 映射：实现了明文目录与密文目录的 1:1 结构映射，大幅优化了目录层级的管理与增量同步效率。\n'
                    '• 确定性文件名加密机制：基于固定 IV 的 AES-256-GCM 算法加密文件名并 Base64Url 编码，解决同步时的文件名冲突与重复识别问题。\n'
                    '• 流式分块加密：数据加密改用分块处理（默认 64KB 为一块），每块 Nonce 动态派生，杜绝重放攻击且减少存储开销。\n'
                    '• 多线程性能提升：密集的 CPU 运算任务通过 Isolate.run() 移交至后台并发执行，防止卡顿 UI。\n\n'
                    '🚀 Performance & UI\n'
                    '• 极致的保险箱解锁速度：下调默认 KDF 派生参数，配合异步计算，实现秒级开启。\n'
                    '• 主页数据概览真实化：引入 StatsService 扫描本地保险箱与缓存区，计算真实存储体积。\n'
                    '• 缓存策略与换算：统计结果缓存至 SharedPreferences，实现“零延迟”读取，智能换算 MB 与 GB。\n'
                    '• UI 布局更新：主页改版为左右横向结构，左侧放置统计饼图卡片。\n'
                    '• 新建文件夹功能：补全了保险箱内部基础目录管理能力。'
                ),
              ),
            ],
          ),
          ExpansionTile(
            title: Text('版本 1.1.2 (2026-04-16)'),
            children: [
              ListTile(
                title: Text(
                    '✨ UI & Workflow\n'
                    '• 主页数据可视化：引入 fl_chart 图表库，构建了美观的环形饼图模块展示数据。\n'
                    '• 设置页拓展与日志沉淀：添加“关于”模块与手风琴折叠交互的“更新日志”专属页面。\n'
                    '• 加密任务进度看板：右上角增设动态同步图标，点击弹出多层级支持目录树展开的进度面板，附带进度条与容量百分比。\n'
                    '• CI/CD 修复：解决 webdav_client API 破坏性变更导致的编译报错，替换为原生 HttpClient 实现。'
                ),
              ),
            ],
          ),
          ExpansionTile(
            title: Text('版本 1.1.1 (2026-04-16)'),
            children: [
              ListTile(
                title: Text(
                    '🐛 Bug Fixes & Optimizations\n'
                    '• 后台隔离优化：修复部分重量级计算卡死主线程导致 ANR 的风险。\n'
                    '• 基准测试加强：修复进度条视觉 Bug，新增实时文本展示，实现多核并行测试。\n'
                    '• 云盘交互重构：优化列表交互，新增“编辑”按钮与安全等级提示警告。'
                ),
              ),
            ],
          ),
          ExpansionTile(
            title: Text('版本 1.1.0 (2026-04-16)'),
            children: [
              ListTile(
                title: Text(
                    '✨ Core Vault Features\n'
                    '• 独立加密保险箱管理：支持从零创建、配置、列表总览及解锁。\n'
                    '• 高自由度加密协议矩阵：支持 AES-256-GCM / ChaCha20-Poly1305 及 PBKDF2 / Argon2id / Scrypt。\n'
                    '• 明文配置文件机制：生成 vault_config.json 支持跨设备迁移。\n'
                    '• 硬件基准测试：新增一键式硬件性能评估工具，展示真实加密速度。\n'
                    '• 赛博朋克主题全面升级：高对比度霓虹配色深度适配。'
                ),
              ),
            ],
          ),
          ExpansionTile(
            title: Text('版本 1.0.2 (2026-04-16)'),
            children: [
              ListTile(
                title: Text(
                    '✨ Permissions & Styling\n'
                    '• 原生文件选择器集成：接入系统级文件选择器，支持单选/多选/文件夹。\n'
                    '• 动态存储权限适配：兼容 Android 11+ MANAGE_EXTERNAL_STORAGE。\n'
                    '• 双轨主题架构：完成系统默认与赛博朋克深色主题双轨适配。'
                ),
              ),
            ],
          ),
          ExpansionTile(
            title: Text('版本 1.0.1 (2026-04-16)'),
            children: [
              ListTile(
                title: Text(
                    '✨ WebDAV & Security Infrastructure\n'
                    '• WebDAV 全生命周期管理：支持增删改查。\n'
                    '• 硬件级安全等级检测：根据设备是否支持硬件 Keystore 划分等级。\n'
                    '• 混合持久化存储方案：敏感凭证保存于 flutter_secure_storage。\n\n'
                    '🐛 Bug Fixes & CI\n'
                    '• 主题状态同步修复：修复底部导航频繁切换时主题按钮状态不同步问题。\n'
                    '• CI 签名配置劫持修复：确保云端编译 APK 签名哈希一致。\n'
                    '• 工作流安全锁：缺失签名密钥时强制拦截终止构建。'
                ),
              ),
            ],
          ),
          ExpansionTile(
            title: Text('版本 1.0.0'),
            children: [
              ListTile(
                title: Text(
                    '• 项目启航：初始版本发布，完成基础脚手架搭建与核心 Tab 路由。'
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
