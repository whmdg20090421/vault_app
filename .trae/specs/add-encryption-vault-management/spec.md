# 加密模块（Vault）管理功能 Spec

## Why
用户需要正式启动核心加密功能。当前加密页面仅能单次选择文件/文件夹，未形成“加密保险箱”（Vault）的概念。用户需要创建一个加密文件夹，将其作为加密内容的统一存放地。并要求能够自由配置该保险箱的名称、密码、加密算法、抗暴力破解模式（KDF）及相关参数、以及是否加密文件名的开关。

## What Changes
- 全局重构“赛博朋克”主题（位于 `lib/main.dart`）：抛弃单纯的黑色主题，重新设计具备真实赛博朋克风格的全局 `ThemeData`（如霓虹黄、青色、品红等高对比度色彩，增加发光效果或特殊的边框样式）。
- 修改 `lib/encryption/encryption_page.dart`，使其展示已配置的“加密文件夹”（Vault）列表。底部添加一个全局加号按钮（FAB），点击后调用目录选择器选择一个本地文件夹。
- 新增 `lib/encryption/vault_config_page.dart`，用户选择文件夹后跳转至此页。页面包含：
  - 右上角提供一个“测试（Benchmark）”图标。点击后将生成一个 500MB 的临时测试文件，允许用户选择加密算法并执行加密测试，最终给出该算法的平均加密速度（MB/s），以帮助用户评估性能。
  - 保险箱名称输入框。
  - 密码输入及确认框。
  - 加密模式选择：如 `AES-256-GCM`，`ChaCha20-Poly1305` 等。
  - 抗暴力破解模式（KDF）选择：`None`，`PBKDF2`，`Scrypt` 等。
  - 如果选择了 KDF，则在下方展开静态参数面板，预填默认安全数值（如 `PBKDF2` 的 iterations = 100000，`Scrypt` 的 N = 16384, r = 8, p = 1）。
  - “是否加密文件名”开关：开启时加密文件名和内容，关闭时只加密内容。
- 确认配置后，将这些参数以明文 JSON 格式保存至该文件夹根目录下的 `vault_config.json` 文件中。为了后续验证密码，配置内需包含由用户密码及所选算法加密的特定验证密文（如 `validation_ciphertext` 和对应的 `salt`/`nonce`）。
- 在“加密”导航栏列表中点击创建好的 Vault 时，弹出密码输入对话框。
- 输入密码后，系统读取 `vault_config.json` 并尝试解密验证块，成功后跳转至 `lib/encryption/vault_explorer_page.dart`。
- 在 `VaultExplorerPage` 内部，右下角放置一个加号（FAB），原有的“导入文件”和“导入明文文件夹”功能移入其中，并新增“新建文件夹”以供分类整理。

## Impact
- Affected specs: `add-file-picker-for-encryption` 的部分 UI（选择明文文件/文件夹的按钮）将被迁移或重构成 FAB 菜单。
- Affected code:
  - `lib/encryption/encryption_page.dart` (重构为列表)
  - `lib/encryption/vault_config_page.dart` (新增)
  - `lib/encryption/vault_explorer_page.dart` (新增)
  - `lib/encryption/models/vault_config.dart` (新增)
  - `pubspec.yaml` (新增加密依赖 `crypto`, `pointycastle`, `shared_preferences` 以存储保险箱路径)

## ADDED Requirements
### Requirement: Vault Configuration
系统应当提供一个 UI 界面来配置保险箱参数，并在选定目录的根目录下将配置保存为 `vault_config.json`。
#### Scenario: Success case
- **WHEN** 用户选择了一个目录并填写了名称、密码、加密算法及 KDF 参数
- **THEN** 系统根据密码及 KDF 派生密钥，加密一段校验字符串，并将完整配置明文（含 KDF 参数、salt 和校验密文）保存至 `vault_config.json`，然后在列表中展示该保险箱。

### Requirement: Encryption Performance Benchmark
系统应当提供一个测速工具，供用户在配置页面评估所选加密算法的实际速度。
#### Scenario: Success case
- **WHEN** 用户在配置页面点击右上角的测试图标并选择某个算法（如 ChaCha20）
- **THEN** 系统在临时目录创建一个 500MB 文件并执行流式加密，最终弹窗显示加密耗时与平均速度（如 `150 MB/s`），避免 OOM 的同时给出准确参考。
系统在用户点击保险箱时必须要求输入密码，并在解密验证成功后进入文件管理器界面。
#### Scenario: Success case
- **WHEN** 用户点击保险箱并输入正确密码
- **THEN** 系统派生密钥并验证配置中的密文成功，跳转至 `VaultExplorerPage`，页面右下角的加号菜单包含导入文件、导入文件夹及新建文件夹的功能。