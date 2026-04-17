# Tasks

- [x] Task 1: 排查并修复全局背景闪回默认底色
  - [x] SubTask 1.1: 定位背景渲染入口（当前在 `MaterialApp.builder` 的 Stack 中），梳理其在 Route/Overlay 更新时的重建链路与潜在的 image decode 空窗
  - [x] SubTask 1.2: 将背景层提取为可复用且稳定的独立组件（稳定 `ImageProvider`，支持 `gaplessPlayback`，必要时 `RepaintBoundary`）
  - [x] SubTask 1.3: 增加背景预缓存策略（App 启动后或切换背景图时 `precacheImage`），并确保缓存命中不因 rebuild 失效
  - [x] SubTask 1.4: 审计并修复所有弹窗/底部面板/新页面的背景透明策略（Dialog/BottomSheet/Route），避免过渡动画期间出现非透明默认底色遮挡

- [x] Task 2: 增加“背景闪烁回归验证”能力
  - [x] SubTask 2.1: 增加最小化 widget 测试或集成测试：打开 Dialog/BottomSheet/Push 新页面时背景层仍存在（可通过查找背景层 key/Widget 或截图对比的方式验证，优先选择工程现有测试范式）
  - [x] SubTask 2.2: 增加开发期自检开关/日志（仅 debug）：记录背景层是否发生 image provider 重新解析与是否命中缓存（确保不记录任何敏感信息）

- [x] Task 3: 编译期版本号自动正则替换（Automated Regex Version Injection）
  - [x] SubTask 3.1: 新增版本同步脚本：从 `pubspec.yaml` 读取目标版本号与 build number，定义“需要同步的文件列表/规则”（例如：Android Gradle、README、CHANGELOG 等）
  - [x] SubTask 3.2: 脚本执行时进行全仓扫描与替换，并在结束时做“残留旧版本号”验证；失败时输出文件路径与命中的字段位置（行号）
  - [x] SubTask 3.3: 将脚本接入 GitHub Actions（build 与 release workflow），确保每次构建/发布都强制执行并作为 gate

- [x] Task 4: 差异化 GitHub 更新日志发布（Differentiated Changelog Deployment）
  - [x] SubTask 4.1: 定义 README 摘要区的规范（固定位置/固定标题），并明确摘要来源（优先来自对应版本的 changelog 文档或 release notes）
  - [x] SubTask 4.2: 在发布流程中自动更新 README 摘要，并插入“查看完整更新明细”的链接（指向 GitHub Releases 对应 tag 或 `docs/changelogs/<version>.md`）
  - [x] SubTask 4.3: 更新 release workflow：生成 Release body（详尽明细），并确保 README 摘要与 Release 明细一致

# Task Dependencies
- Task 1 与 Task 2 依赖关系：Task 2 依赖 Task 1 完成后才能稳定编写验证。
- Task 3 与 Task 4 可并行，但 Task 4 通常需要复用 Task 3 的版本解析能力。
