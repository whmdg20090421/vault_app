# 摘要
修复导入文件夹时加密任务进度为0%且不消耗CPU的问题，并增加导入已有保险箱（检测 `vault_config.json`）的机制，防止重新安装后数据丢失或被覆盖。

# 现状分析
1. **导入文件夹进度为0%的问题**：
   在 `vault_explorer_page.dart` 的 `doImportFolderIsolate` 方法中，当构建好文件夹的树状结构后，通过 `sendPort` 发送 `{'type': 'tree', 'tree': treeMap}` 消息。但 UI 线程在接收消息时，强制解析 `final tid = message['taskId'] as String;`，由于消息体中缺少 `taskId` 字段，导致触发 `TypeError` 异常。该异常中断了整个 `listen` 监听回调，使得后续所有的 `progress` 更新全部失效，从而导致进度条永远卡在 0%。
2. **重新安装无法读取原有配置的问题**：
   在 `encryption_page.dart` 的 `_pickFolderAndConfig` 方法中，用户选择文件夹后，代码直接无条件跳转到 `VaultConfigPage` 强制要求创建新的保险箱配置。如果该文件夹下已经存在 `vault_config.json`，强行新建会导致新的配置覆盖原有的盐值和随机数等加密参数，导致原有加密文件彻底无法解密。

# 提出的更改
## 1. 修复文件夹加密进度丢失及任务中断问题
- **文件**: `lib/encryption/vault_explorer_page.dart`
- **内容**: 
  - 定位到 `doImportFolderIsolate` 方法中发送 `tree` 消息的代码行。
  - 将 `sendPort.send({'type': 'tree', 'tree': treeMap});` 修改为 `sendPort.send({'type': 'tree', 'taskId': taskId, 'tree': treeMap});`。
  - **原因**: 补全缺失的 `taskId` 参数，防止 UI 线程的进度监听器抛出类型转换异常，从而让后台的加密任务能够顺畅地将进度反馈给界面。

## 2. 增加已有保险箱配置检测与自动导入机制
- **文件**: `lib/encryption/encryption_page.dart`
- **内容**: 
  - 修改 `_pickFolderAndConfig` 方法，在用户通过 `FilePicker` 选择了目录路径后，优先实例化并检查 `File('$result/vault_config.json')` 是否存在。
  - **如果存在**：直接将该目录路径写入到 `SharedPreferences` 的 `vault_paths` 列表中（去重）。随后弹出 SnackBar 提示“检测到已有保险箱，已自动导入配置”，并调用 `_loadVaults()` 刷新首页列表，最后 `return` 结束该方法。
  - **如果不存在**：保留原有逻辑，跳转到 `VaultConfigPage` 引导用户进行全新的保险箱参数配置。
  - **原因**: 保障用户重装 App 后能通过选择旧目录无缝找回数据，防止配置被意外覆盖。

# 假设与决策
- **假设**：只要选中的目录下存在 `vault_config.json` 文件，就默认这是一个已经配置好的有效保险箱，用户意图为恢复该保险箱而不是覆盖重写。
- **决策**：直接阻断覆盖写入流程并自动导入配置，这在文件加密类应用中是最安全、对用户最友好的做法。

# 验证步骤
1. **测试已有保险箱导入**：选择一个以前创建过并包含 `vault_config.json` 的目录，验证应用是否直接将其添加到列表中，并确保可以正常输入旧密码解锁读取文件。
2. **测试全新保险箱创建**：选择一个空文件夹，验证是否正常跳转到配置页面。
3. **测试文件夹加密进度**：进入解锁后的保险箱，选择导入一个包含若干文件的本地文件夹，打开任务面板，观察进度条是否正常增长，并在最终确认所有文件成功导入。