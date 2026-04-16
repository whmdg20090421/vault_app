# Tasks

- [ ] Task 1: 准备底层模型与加密依赖库
  - [ ] SubTask 1.1: 在 `pubspec.yaml` 中添加所需加密依赖，如 `crypto`, `pointycastle` 等，用于支持 AES-256-GCM、ChaCha20-Poly1305 以及 PBKDF2/Scrypt/Argon2 等 KDF。同时添加 `shared_preferences` 以存储保险箱路径列表。
  - [ ] SubTask 1.2: 创建 `lib/encryption/models/vault_config.dart`，定义序列化的 Vault 配置实体类（`VaultConfig`）。包含：加密算法类型、KDF 类型及其动态参数（iterations, N, r, p 等）、文件名加密标识（bool）和验证块数据（salt, nonce, ciphertext）。

- [ ] Task 2: 实现 VaultConfigPage 与本地配置写入逻辑
  - [ ] SubTask 2.1: 创建 `lib/encryption/vault_config_page.dart`。包含名称、密码、密码确认框、加密模式下拉菜单、KDF 模式下拉菜单。
  - [ ] SubTask 2.2: 在 `VaultConfigPage` 中，当 KDF 选中时，在其下方展开子选项静态参数面板，并预填默认安全数值。
  - [ ] SubTask 2.3: 添加“是否加密文件名”的 Switch 拨动开关。
  - [ ] SubTask 2.4: 在点击确认时，调用加密库生成 KDF 派生密钥，对已知字符串（如 "VAULT_VALID"）进行加密生成验证密文，然后将整个 `VaultConfig` 序列化为明文 JSON，写入所选文件夹根目录的 `vault_config.json` 中。
  - [ ] SubTask 2.5: 使用 `SharedPreferences` 保存该保险箱的路径到全局列表中，以便主页读取。

- [ ] Task 3: 重构主页 (EncryptionPage) 的列表与解锁交互
  - [ ] SubTask 3.1: 将 `EncryptionPage` 重构为展示已配置保险箱（Vault）的列表视图。列表项展示保险箱名称及其路径。
  - [ ] SubTask 3.2: 将之前的“选择文件/文件夹”的两个按钮修改为一个右下角的全局悬浮加号按钮（FAB）。点击后选择目录（文件夹），成功后跳转至 `VaultConfigPage`。
  - [ ] SubTask 3.3: 增加列表项点击的解锁弹窗。弹窗要求输入密码，读取对应目录下的 `vault_config.json`。
  - [ ] SubTask 3.4: 根据输入的密码及读取到的 KDF 参数进行密钥派生，尝试解密配置中的 `validation_ciphertext`。若解密成功，则进入 `VaultExplorerPage`；否则提示密码错误。

- [ ] Task 4: 实现 VaultExplorerPage 及其内部悬浮菜单
  - [ ] SubTask 4.1: 创建 `lib/encryption/vault_explorer_page.dart`，供解密成功后跳转。传入保险箱配置与派生好的主密钥。
  - [ ] SubTask 4.2: 页面主体目前可暂时为一个空白占位列表（用于展示后续加密的文件）。
  - [ ] SubTask 4.3: 在页面右下角增加一个展开式的 FAB 菜单（使用 `ExpandableFab` 或 `PopupMenuButton` / `BottomSheet`）。
  - [ ] SubTask 4.4: 将原先在 `EncryptionPage` 中的“导入明文文件”、“导入明文文件夹”功能移入该菜单，并新增一个“新建空文件夹”按钮，方便在此保险箱内进行分类整理。