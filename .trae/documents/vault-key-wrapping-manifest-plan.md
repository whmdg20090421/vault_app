# 计划：Vault 密钥包裹（改密不重加密）+ 加密清单（结构书）+ 去重导入

## 总结

实现 3 组能力：

1. **密钥架构升级（KEK/DEK）**：引入系统随机生成的数据密钥 DEK(A) 用于文件内容/文件名加密；用户密码通过 KDF 派生出 KEK(B) 用于包裹（加密）DEK 得到 C。解锁时用 B 解密 C 得到 A，再用 A 解密文件。改密时默认只更新 C（不重加密文件）；提供一个可选勾选项“重新加密（生成新 DEK 并轮换加密）”。
2. **结构书（清单）**：在 Vault 内以加密形式保存一份“从根到每个文件/文件夹”的清单，包含路径、大小、修改时间、加密前/后哈希（SHA-256）、以及导入来源绝对路径（加密存储）。
3. **导入去重**：导入文件夹时，先计算加密前 SHA-256，与清单/索引比对；同路径同哈希直接跳过；同哈希不同路径视为复制/移动，执行“密文秒传复制”；并输出一份差异统计（新增/修改/跳过/疑似移动或复制）。

## 现状分析（基于代码检索）

### 现有 key 来源与校验方式（无 DEK 包裹）

- Vault 创建时写入明文配置文件 `vault_config.json`，字段由 [vault_config.dart](file:///workspace/lib/encryption/models/vault_config.dart) 定义并由 [vault_config_page.dart](file:///workspace/lib/encryption/vault_config_page.dart) 生成。
- 现状 **masterKey = KDF(password, salt, kdfParams)**（32 bytes），用于：
  - 文件内容分块 AES-256-GCM（Nonce 由 fileId 与 chunkIndex 派生）：[chunk_crypto.dart](file:///workspace/lib/encryption/utils/chunk_crypto.dart#L33-L109)
  - 文件名“确定性加密”（固定全 0 nonce）：[encrypted_vfs.dart](file:///workspace/lib/vfs/encrypted_vfs.dart#L129-L142)
- 解锁：从 `vault_config.json` 取 `salt/nonce/kdf/kdfParams/validationCiphertext`，派生 key 后解密 magic 校验，成功则进入 Vault：[encryption_page.dart](file:///workspace/lib/encryption/encryption_page.dart#L134-L246)。
- 现状没有“修改密码/改密轮换”的入口与实现（搜索未命中）。

### 现有索引

- 本地索引是 `local_index.json`（位于 vaultDirectoryPath 下），由 [local_index_service.dart](file:///workspace/lib/encryption/services/local_index_service.dart) 读写。
- 当前加密 worker 在写入密文后计算“加密后”MD5 并写入索引：[encryption_task_manager.dart](file:///workspace/lib/encryption/services/encryption_task_manager.dart#L639-L691)。

## 目标与成功标准

### 目标 1：路径存储不明文

- **成功标准**：索引与清单中不出现明文绝对路径；需要比对路径时在解锁状态下用 DEK 解密后比对。

### 目标 2：DEK/KEK 包裹与改密

- **成功标准**：
  - 新建 Vault：文件内容/文件名加密均使用 DEK(A)，而不是直接使用 KDF(password) 的输出。
  - 解锁：输入密码可解出 DEK(A)，并正常打开/导入/解密文件。
  - 修改密码（不勾选重新加密）：不重写任何密文文件，更新配置后仍可解锁并读写历史密文。
  - 修改密码（勾选重新加密）：生成新 DEK，完成内容与文件名轮换（全量重加密），并成功更新配置。

### 目标 3：结构书（清单）与导入去重

- **成功标准**：
  - Vault 内存在一个加密清单文件（例如 `/.vault_manifest`），记录每个文件/文件夹的路径、大小、mtime、加密前 SHA-256、加密后 SHA-256。
  - 导入时：同路径同哈希跳过；同哈希不同路径走密文复制秒传；不同哈希正常加密；输出统计。

## 方案设计（决策已锁定）

### A. Vault 配置文件 schema 升级（vault_config.json）

新增字段并引入版本号（向后兼容）：

- `version`: `2`
- `kekSaltBase64Url`：用于 KEK 的 salt（可复用现有 `salt` 字段，也可改名；本计划采用“新增字段 + 兼容旧字段”的方式）
- `kekKdf`, `kekKdfParams`：保留现有 KDF 选择与参数
- `kekValidationNonceBase64Url`, `kekValidationCiphertextBase64`：可复用现有 `nonce/validationCiphertext` 作为密码校验
- `wrappedDekNonceBase64Url`：包裹 DEK 时使用的随机 nonce（12 bytes）
- `wrappedDekCiphertextBase64`：`AES-256-GCM(KEK, wrappedDekNonce, DEK)` 的密文
- `algorithm`：文件内容加密算法（现有字段；仍用于 DEK 选择）
- `encryptFilename`：是否加密文件名（现有字段；仍由 DEK 生效）

兼容策略：
- 若 `version` 缺失或为 `1`：保持旧逻辑（masterKey = deriveKey(password)），但计划中会提供迁移：首次解锁后生成 DEK 并写回 `version=2`（可选，需在实现阶段决定是否自动迁移或提示迁移）。

涉及文件：
- [vault_config.dart](file:///workspace/lib/encryption/models/vault_config.dart)
- [vault_config_page.dart](file:///workspace/lib/encryption/vault_config_page.dart)
- [encryption_page.dart](file:///workspace/lib/encryption/encryption_page.dart)
- [sync_settings_dialog.dart](file:///workspace/lib/cloud_drive/sync_settings_dialog.dart)
- [sync_config_page.dart](file:///workspace/lib/cloud_drive/sync_config_page.dart)

### B. 解锁流程变更（从密码得到 DEK）

解锁步骤（version=2）：
1. `KEK = KDF(password, kekSalt, kdfParams)`（复用现有 [CryptoUtils.deriveKey](file:///workspace/lib/encryption/utils/crypto_utils.dart#L33-L81)）
2. 校验密码：
   - 方式 1（兼容现状）：解密 `validationCiphertext` 得到 magic（见 [encryption_page.dart](file:///workspace/lib/encryption/encryption_page.dart#L188-L207)）
   - 方式 2（更简洁）：尝试解密 `wrappedDekCiphertext`；成功即认为密码正确
   - 本计划采用：**两者都支持**（优先 unwrap DEK；若字段缺失则回退到 validationCiphertext）
3. `DEK = AES-GCM-Decrypt(KEK, wrappedDekNonce, wrappedDekCiphertext)`
4. `DEK` 作为 `masterKey` 传给 `EncryptedVfs` 与导入 worker（替换现状的 derivedKey）

### C. 修改密码（不重加密 vs 重新加密）

入口：
- 在 Vault 浏览页面的长按菜单中加入“修改密码”（实现位置需在执行阶段确定具体 Widget；候选：Vault 列表项 or VaultExplorerPage 顶部菜单）。

交互：
- 输入：原密码、两次新密码
- 复选框：`重新加密（生成新 DEK）`，勾选时需二次确认

逻辑：
- 不勾选重新加密：
  1. 用原密码派生 KEK_old，解出 DEK_old
  2. 用新密码派生 KEK_new
  3. 重新随机生成 `wrappedDekNonce`，计算 `wrappedDekCiphertext = Encrypt(KEK_new, nonce, DEK_old)`
  4. 同时更新校验密文与相关 salt/nonce（建议：生成新 kekSalt 与 validationNonce，防止离线枚举）
  5. 写回 `vault_config.json`，不触碰任何密文文件
- 勾选重新加密：
  1. 解出 DEK_old
  2. 生成 DEK_new（32 bytes Random.secure）
  3. 全量轮换：遍历 Vault 虚拟路径，逐文件 `open()`（旧 DEK 解密）并 `uploadStream()`（新 DEK 加密写回），同时完成目录/文件名映射轮换
  4. 轮换成功后，用新密码包裹 DEK_new 写回配置
  5. 失败回滚策略：采用临时目录/双写 + 完成后原子替换（执行阶段细化）

### D. 结构书（加密清单）设计

存储位置：
- Vault 根目录下的一个“普通加密文件”（虚拟路径固定），例如：`/.vault_manifest`
- 由于它写在加密域（`initEncryptedDomain('/')`）下，会随 Vault 一并加密存储（内容加密；文件名是否加密取决于 `encryptFilename`，但可通过确定性加密稳定定位）

清单内容（JSON，按 remotePath 做 key，便于查找与 diff）：
- `remotePath`：明文虚拟路径（例如 `/小说/第1章.txt`）
- `type`: `file|folder`
- `size`：明文大小（文件为原始大小；文件夹为聚合大小）
- `mtime`：明文文件/文件夹的 lastModified（ISO8601）
- `hashBeforeSha256`：导入源文件的 SHA-256（文件）
- `hashAfterSha256`：密文文件的 SHA-256（文件）
- `encryptedSize`、`encryptedMtime`：密文侧元数据（文件）
- `sourceAbsolutePathEnc`：导入源绝对路径（用 DEK 加密后的字符串，满足“加密存储绝对路径”决策）

涉及新增/修改文件（执行阶段创建）：
- `lib/encryption/services/vault_manifest_service.dart`（新增）
- 可能拆出 `lib/encryption/models/vault_manifest.dart`（新增）

### E. 导入去重逻辑（SHA-256 + 秒传复制）

策略：
- 每个文件在加密前先计算 `hashBeforeSha256`
- 从清单/索引加载历史记录，查找是否存在相同 `hashBeforeSha256`
  - 同 hash + 同路径（解密后的绝对路径一致或 remotePath 一致）：标记为 `skipped`
  - 同 hash + 不同路径：判定为 `moved/copied`，执行“密文复制”：
    - 通过 `EncryptedVfs.getRealPath(oldRemotePath/newRemotePath)` 找到密文文件真实路径
    - 在底层文件系统直接 `copy()` 密文文件（避免再次加密）
- 若未命中：正常加密写入

落盘：
- 无论是正常加密还是秒传复制，都会计算 `hashAfterSha256` 并更新清单/索引

涉及文件：
- [encryption_task_manager.dart](file:///workspace/lib/encryption/services/encryption_task_manager.dart)
- [local_index_service.dart](file:///workspace/lib/encryption/services/local_index_service.dart)

## 文件级变更清单（执行阶段逐一落实）

1. [vault_config.dart](file:///workspace/lib/encryption/models/vault_config.dart)
   - 增加 `version` 与 DEK 包裹字段（wrappedDekNonce/wrappedDekCiphertext 等）
   - 增加兼容旧版字段映射
2. [vault_config_page.dart](file:///workspace/lib/encryption/vault_config_page.dart)
   - 创建 Vault 时生成 DEK，并用 KEK 包裹后写入配置
3. [encryption_page.dart](file:///workspace/lib/encryption/encryption_page.dart)
   - 解锁逻辑改为解出 DEK 作为 masterKey 传递
4. [sync_settings_dialog.dart](file:///workspace/lib/cloud_drive/sync_settings_dialog.dart)、[sync_config_page.dart](file:///workspace/lib/cloud_drive/sync_config_page.dart)
   - 同步场景的解锁/校验与 key 获取改为 DEK
5. [encrypted_vfs.dart](file:///workspace/lib/vfs/encrypted_vfs.dart)
   - 不改存储格式，但需要确保清单文件可稳定定位（必要时引入固定文件名策略）
6. [encryption_task_manager.dart](file:///workspace/lib/encryption/services/encryption_task_manager.dart)
   - worker：计算 SHA-256（前/后），并对接清单/索引做去重与秒传复制
7. [local_index_service.dart](file:///workspace/lib/encryption/services/local_index_service.dart)
   - 从“仅记录密文哈希”升级为“记录前/后哈希 + 绝对路径（加密存储）+ 时间/大小”
8. 新增清单服务（待创建）
   - 负责读取/写入 `/.vault_manifest`，提供查询与更新接口
9. UI：加入“修改密码”
   - 新增弹窗（原密码/新密码/确认/重新加密勾选与二次确认）
   - 触发配置更新或轮换流程

## 安全与隐私注意点（落地约束）

- **不在任何日志中输出**：password、KEK、DEK、wrappedDekCiphertext。
- 导入源绝对路径只以 **DEK 加密后的密文**存入清单/索引（符合你选择的“加密存储”）。
- 哈希用于去重与完整性记录：采用 SHA-256（符合你选择）。

## 验证与验收（执行阶段）

1. 新建 Vault（version=2）
   - 解锁成功；导入加密成功；关闭 App 重开后仍可解锁读写
2. 修改密码（不勾选重新加密）
   - 用新密码可解锁；旧密码不可解锁；既有文件可正常读取（说明未重加密也可用）
3. 修改密码（勾选重新加密）
   - 全量轮换后可解锁；既有文件可正常读取；清单/索引更新为新哈希与新 wrappedDEK
4. 去重导入
   - 重复导入同一文件夹：大量文件被跳过；统计结果正确
   - 同内容不同路径：触发密文复制，不走再加密
5. 清单可读性
   - 解锁后可从 Vault 内读取清单并展示（后续 UI 需求可再扩展）

