# Tasks
- [x] Task 1: 初始化全局代码扫描与问题发现
  - [x] SubTask 1.1: 启动一个“查找分析 Agent”，在全局代码中搜索残留的未使用的函数、断裂的函数、可能报错的代码或接口不兼容的函数。
  - [x] SubTask 1.2: 使用静态分析工具（例如 `dart analyze` / `flutter analyze` 等，或根据实际环境选择可用的方式）导出所有的错误与警告列表。
- [x] Task 2: 应用最佳实践与安全检查
  - [x] SubTask 2.1: 启动一个“最佳实践与安全 Agent”，重点检查 `vercel-react-best-practices` 和 `security-best-practices` 在项目中的落实情况（针对本项目的 Dart/Flutter 框架，重点查找诸如敏感数据处理、UI 渲染性能、内存泄露等问题）。
- [x] Task 3: 多 Agent 协同修复问题
  - [x] SubTask 3.1: 汇总 Task 1 和 Task 2 发现的所有代码问题，按文件/模块进行归类。
  - [x] SubTask 3.2: 启动多个“修复 Agent”（可并行或依次执行），针对这些文件逐一修复接口不兼容、移除残留函数或修正错误调用。
- [x] Task 4: 总控 Agent 进行最终代码 Review 和双重保险验证
  - [x] SubTask 4.1: 收集修复后产生的所有文件变更记录。
  - [x] SubTask 4.2: 运行全局代码检查（如重新执行 `flutter analyze` 或直接读取文件对比），确认没有引入新的崩溃、残留和接口断裂。
  - [x] SubTask 4.3: 如有必要，进行本地编译或相关测试以验证整个修复的闭环流程。

# Task Dependencies
- [Task 3] depends on [Task 1] and [Task 2]
- [Task 4] depends on [Task 3]
