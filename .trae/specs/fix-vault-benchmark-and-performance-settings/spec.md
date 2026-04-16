# 加密配置卡死与性能测试优化 Spec

## Why
当前 Vault 配置页在点击“创建并保存”后可能因 KDF/验证块计算在 UI 线程执行而导致卡死并触发 ANR。同时 Benchmark 进度条出现 >100% 的溢出，并且单线程加密导致性能测试无法利用多核。

## What Changes
- 修复：创建并保存时的计算任务（KDF 派生 + 校验密文生成）迁移到后台执行，UI 保持可响应并持续显示保存中状态。
- 修复：Benchmark 进度计算，确保进度永远在 0%~100% 内，且与实际处理量一致。
- 优化：Benchmark 加密逻辑改为多线程（多 isolate 并行）执行，减少单核满载导致的速度偏低问题。
- 新增：性能设置页（入口位于性能测试相关 UI 之后），支持配置“Benchmark 使用的核心数量”，并持久化保存。

## Impact
- Affected specs: [add-encryption-vault-management](../add-encryption-vault-management/spec.md)
- Affected code:
  - `lib/encryption/vault_config_page.dart`（保存逻辑与 Benchmark 逻辑）
  - `lib/encryption/utils/crypto_utils.dart`（支持 isolate 友好的纯函数封装/参数序列化）
  - `lib/encryption/` 新增性能设置页与配置存储（如 `performance_settings_page.dart`）
  - `shared_preferences`（新增性能设置项存储键）

## ADDED Requirements
### Requirement: 性能设置页
系统 SHALL 提供一个“性能设置”页面，用于配置 Benchmark 使用的核心数量，并在应用重启后保持该设置。

#### Scenario: 打开与展示
- **WHEN** 用户从性能测试相关入口进入“性能设置”
- **THEN** 页面展示“核心数量配置”行，格式为“(当前可使用的核心数/系统总核心数)”。
- **AND** 页面提供一个进度条（Slider）与一个输入框（TextField）用于调整核心数量，两者数值保持同步。

#### Scenario: 限制规则
- **WHEN** 用户输入或拖动调整核心数量
- **THEN** 核心数量必须满足：`>= 1` 且 `<= (系统最大核心数 - 1)`。
- **AND** 若用户输入非法值，系统应自动纠正到合法范围（或提示并回退到最近合法值）。

#### Scenario: 持久化
- **WHEN** 用户修改核心数量配置
- **THEN** 系统将其持久化到本地（SharedPreferences），并在后续 Benchmark 中生效。

### Requirement: Benchmark 多线程与进度正确性
系统 SHALL 在 Benchmark 中按用户配置的核心数进行并行加密测试，并保证进度显示准确。

#### Scenario: 多线程执行
- **WHEN** 用户开始 Benchmark
- **THEN** 系统根据“性能设置”中的核心数启动多个并行 worker（isolate），并对 500MB 测试数据执行加密基准测试。
- **AND** 结果仍以 MB/s 形式显示。

#### Scenario: 进度不溢出
- **WHEN** Benchmark 执行过程中更新进度条
- **THEN** UI 显示的百分比不得超过 100%，并在完成时稳定显示 100%。

## MODIFIED Requirements
### Requirement: 创建并保存不应卡死
系统 SHALL 在创建 Vault 并保存 `vault_config.json` 时保持 UI 响应，不得触发 ANR。

#### Scenario: PBKDF2/Scrypt/Argon2 参数较重
- **WHEN** 用户设置较高的 KDF 参数并点击“创建并保存”
- **THEN** UI 仍可滚动/可响应返回键/不会被系统判定为无响应。
- **AND** 保存期间展示明确的加载状态（如按钮禁用 + ProgressIndicator）。
- **AND** 保存成功/失败均可正常结束加载状态并给出提示。

