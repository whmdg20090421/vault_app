# Tasks

- [ ] Task 1: 云盘页 UI 改造为 WebDAV 配置管理入口
  - [ ] SubTask 1.1: 将“云盘”Tab 替换为 CloudDrivePage（列表 + 新增入口）
  - [ ] SubTask 1.2: 增加新增/编辑表单页面（命名、URL、账户名、授权密码）
  - [ ] SubTask 1.3: 增加删除交互（含二次确认）

- [ ] Task 2: WebDAV 配置数据模型与持久化
  - [ ] SubTask 2.1: 定义配置模型（含稳定 ID）与 JSON 序列化
  - [ ] SubTask 2.2: 实现本地 JSON 文件存储（读取/写入/迁移空文件）
  - [ ] SubTask 2.3: 接入系统安全存储保存/读取/删除授权密码（按配置 ID 索引）

- [ ] Task 3: 两级安全能力检测与图形化提示
  - [ ] SubTask 3.1: 在首次保存时执行能力检测并持久化检测结果
  - [ ] SubTask 3.2: Level 1 显示正常图标；Level 2 显示黄色警告横幅与警告图标

- [ ] Task 4: 测试与验证
  - [ ] SubTask 4.1: 更新/新增 Widget 测试覆盖：打开云盘页、进入新增页、基本字段校验与保存后列表展示
  - [ ] SubTask 4.2: 增加最小化的存储层单元测试或 widget 测试替身（避免依赖真实安全存储环境）

# Task Dependencies
- Task 2 depends on Task 1.1（页面需要数据源）
- Task 3 depends on Task 2.3（检测结果与安全存储策略关联）
- Task 4 depends on Task 1, Task 2（测试需要 UI 与数据层落地）

