# Tasks

- [x] Task 1: 准备底层模型与加密依赖库，并重构全局赛博朋克主题
  - [x] SubTask 1.1: 在 `pubspec.yaml` 中添加所需加密依赖，如 `crypto`, `pointycastle` 等，以及 `shared_preferences` 以存储保险箱路径列表。
  - [x] SubTask 1.2: 创建 `lib/encryption/models/vault_config.dart`，定义序列化的 Vault 配置实体类（`VaultConfig`）。包含：加密算法类型、KDF 类型及其动态参数（iterations, N, r, p 等）、文件名加密标识（bool）和验证块数据（salt, nonce, ciphertext）。
  - [x] SubTask 1.3: 在 `lib/main.dart` 等核心文件中，重新编写赛博朋克主题。放弃单纯深色模式，使用 `Color(0xFFFCE205)`（霓虹黄）、`Color(0xFF00F0FF)`（青色）、`Color(0xFFFF003C)`（品红）等搭配，给按钮、卡片和边框带来霓虹灯和发光效果。并在全应用强制适配。

- [x] Task 2: 实现 VaultConfigPage 与本地配置写入逻辑
  - [x] SubTask 2.1: 创建 `lib/encryption/vault_config_page.dart`。在 `AppBar` 右上角添加一个“测试（Benchmark）”图标按钮。包含名称、密码、密码确认框、加密模式下拉菜单、KDF 模式下拉菜单。
  - [x] SubTask 2.2: 在 `VaultConfigPage` 中，当 KDF 选中时，在其下方展开子选项静态参数面板，并预填默认安全数值。
  - [x] SubTask 2.3: 添加“是否加密文件名”的 Switch 拨动开关。
  - [x] SubTask 2.4: 实现配置参数写入 `vault_config.json` 的逻辑，并通过 `SharedPreferences` 保存全局路径列表。

- [x] Task 3: 性能测试模块 (Performance Benchmark Module)
  - [x] SubTask 3.1: 点击 `VaultConfigPage` 右上角的测试图标，弹出一个 Dialog 允许用户选择加密算法（如 AES-256-GCM, ChaCha20-Poly1305）。
  - [x] SubTask 3.2: 编写性能测试逻辑：在系统的临时目录下创建（或通过流分块）一个大小为 500MB 的临时测试数据文件（考虑到 Dart 内存限制，必须使用分块 Stream 或类似机制避免 OOM）。
  - [x] SubTask 3.3: 执行加密，记录前后耗时，最后计算并展示平均速度（MB/s）给用户。

- [x] Task 4: 重构主页 (EncryptionPage) 的列表与解锁交互
  - [x] SubTask 4.1: 将 `EncryptionPage` 重构为展示已配置保险箱（Vault）的列表视图。列表项展示保险箱名称及其路径。
  - [x] SubTask 4.2: 将之前的“选择文件/文件夹”的两个按钮修改为一个右下角的全局悬浮加号按钮（FAB）。点击后选择目录（文件夹），成功后跳转至 `VaultConfigPage`。
  - [x] SubTask 4.3: 增加列表项点击的解锁弹窗。弹窗要求输入密码，读取对应目录下的 `vault_config.json`。
  - [x] SubTask 4.4: 根据输入的密码及读取到的 KDF 参数进行密钥派生，尝试解密配置中的 `validation_ciphertext`。若解密成功，则进入 `VaultExplorerPage`；否则提示密码错误。

- [x] Task 5: 实现 VaultExplorerPage 及其内部悬浮菜单
  - [x] SubTask 5.1: 创建 `lib/encryption/vault_explorer_page.dart`，供解密成功后跳转。传入保险箱配置与派生好的主密钥。
  - [x] SubTask 5.2: 页面主体目前可暂时为一个空白占位列表（用于展示后续加密的文件）。
  - [x] SubTask 5.3: 在页面右下角增加一个展开式的 FAB 菜单（使用 `ExpandableFab` 或 `PopupMenuButton` / `BottomSheet`）。
  - [x] SubTask 5.4: 将原先在 `EncryptionPage` 中的“导入明文文件”、“导入明文文件夹”功能移入该菜单，并新增一个“新建空文件夹”按钮，方便在此保险箱内进行分类整理。